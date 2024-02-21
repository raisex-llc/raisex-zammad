# Copyright (C) 2012-2024 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Whatsapp::Webhook::Payload, :aggregate_failures do
  let(:channel) do
    options = {
      app_secret:        Faker::Crypto.sha256,
      verify_token:      Faker::Crypto.sha256,
      callback_url_uuid: Faker::PhoneNumber.cell_phone_in_e164.delete('+'),
    }

    create(:channel, area: 'WhatsApp::Business', options: options, group_id: Group.first.id)
  end

  let(:from) do
    {
      phone: Faker::PhoneNumber.cell_phone_in_e164.delete('+'),
      name:  Faker::Name.unique.name
    }
  end

  let(:user_data) do
    firstname, lastname = User.name_guess(from[:name])

    # Fallback to profile name if no firstname or lastname is found
    if firstname.blank? || lastname.blank?
      firstname, lastname = from[:name].split(%r{\s|\.|,|,\s}, 2)
    end

    {
      firstname: firstname&.strip,
      lastname:  lastname&.strip,
      mobile:    "+#{from[:phone]}",
      login:     from[:phone],
    }
  end

  let(:event) { 'messages' }
  let(:type)  { 'text' }

  let(:raw) do
    {
      object: 'whatsapp_business_account',
      entry:  [{
        id:      '222259550976437',
        changes: [{
          value: {
            messaging_product: 'whatsapp',
            metadata:          {
              display_phone_number: '15551340563',
              phone_number_id:      channel.options[:phone_number_id]
            },
            contacts:          [{
              profile: {
                name: from[:name]
              },
              wa_id:   from[:phone]
            }],
            messages:          [{
              from:      from[:phone],
              id:        'wamid.HBgNNDkxNTE1NjA4MDY5OBUCABIYFjNFQjBDMUM4M0I5NDRFNThBMUQyMjYA',
              timestamp: '1707921703',
              text:      {
                body: 'Hello, world!'
              },
              type:      type
            }]
          },
          field: event
        }]
      }]
    }.to_json
  end

  let(:callback_url_uuid) { channel.options[:callback_url_uuid] }

  let(:signature) do
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), channel.options[:app_secret], raw)
  end

  describe '.verify!' do
    context 'when channel not exists' do
      let(:callback_url_uuid) { 0 }

      it 'raises NoChannelError' do
        expect { described_class.validate!(raw:, callback_url_uuid:, signature:) }.to raise_error(Whatsapp::Webhook::NoChannelError)
      end
    end

    context 'when signatures do not match' do
      let(:signature) { 'foobar' }

      it 'raises ValidationError' do
        expect { described_class.validate!(raw:, callback_url_uuid:, signature:) }.to raise_error(described_class::ValidationError)
      end
    end

    context 'when signatures match' do
      it 'does not raise any error' do
        expect { described_class.validate!(raw:, callback_url_uuid:, signature:) }.not_to raise_error
      end
    end
  end

  describe '.process' do
    let(:data) { JSON.parse(raw) }

    context 'when event is not messages' do
      let(:event) { 'foobar' }

      it 'raises ProcessableError' do
        expect { described_class.process(data:, callback_url_uuid:) }.to raise_error(described_class::ProcessableError)
      end
    end

    context 'when message has errors' do
      let(:raw) do
        {
          object: 'whatsapp_business_account',
          entry:  [{
            id:      '222259550976437',
            changes: [{
              value: {
                messaging_product: 'whatsapp',
                metadata:          {
                  display_phone_number: '15551340563',
                  phone_number_id:      channel.options[:phone_number_id]
                },
                contacts:          [{
                  profile: {
                    name: from[:name]
                  },
                  wa_id:   from[:phone]
                }],
                messages:          [{
                  from:      from[:phone],
                  id:        'wamid.HBgNNDkxNTE1NjA4MDY5OBUCABIYFjNFQjBDMUM4M0I5NDRFNThBMUQyMjYA',
                  timestamp: '1707921703',
                  text:      {
                    body: 'Hello, world!'
                  },
                  errors:    [
                    {
                      message:       '(#130429) Rate limit hit',
                      type:          'OAuthException',
                      code:          130_429,
                      error_data:    {
                        messaging_product: 'whatsapp',
                        details:           '<DETAILS>'
                      },
                      error_subcode: 2_494_055,
                      fbtrace_id:    'Az8or2yhqkZfEZ-_4Qn_Bam'
                    }
                  ],
                  type:      type
                }]
              },
              field: 'messages'
            }]
          }]
        }.to_json
      end

      it 'raises ProcessableError' do
        expect { described_class.process(data:, callback_url_uuid:) }.to raise_error(described_class::ProcessableError)
      end
    end

    context 'when an unsupported type is used' do
      let(:type)  { 'foobar' }

      it 'raises ProcessableError' do
        expect { described_class.process(data:, callback_url_uuid:) }.to raise_error(described_class::ProcessableError)
      end
    end

    context 'when everything is fine', current_user_id: 1 do
      it 'does not raise any error' do
        expect { described_class.process(data:, callback_url_uuid:) }.not_to raise_error
      end

      context 'when no user exists' do
        it 'creates user' do
          described_class.process(data:, callback_url_uuid:)

          expect(User.last).to have_attributes(user_data)
        end
      end

      context 'when user already exists' do
        before do
          user = create(:user, user_data)
          create(:authorization, user: user, uid: user.mobile, provider: 'whatsapp_business')
        end

        it 'does not create a new user' do
          expect { described_class.process(data:, callback_url_uuid:) }.not_to change(User, :count)
        end
      end

      context 'when no ticket exists' do
        it 'creates ticket' do
          described_class.process(data:, callback_url_uuid:)

          expect(Ticket.last).to have_attributes(
            title:    "New WhatsApp message from #{from[:name]} (#{user_data[:mobile]})",
            group_id: channel.group_id,
          )
          expect(Ticket.last.preferences).to include(
            channel_id: channel.id,
          )

          expect(Ticket::Article.last).to have_attributes(
            body: 'Hello, world!',
          )
          expect(Ticket::Article.last.preferences).to include(
            whatsapp: {
              entry_id:   '222259550976437',
              message_id: 'wamid.HBgNNDkxNTE1NjA4MDY5OBUCABIYFjNFQjBDMUM4M0I5NDRFNThBMUQyMjYA',
            }
          )
        end
      end

      context 'when ticket already exists' do
        let(:ticket_state) { 'open' }

        let(:setup) do
          user = create(:user, user_data)
          create(:authorization, user: user, uid: user.mobile, provider: 'whatsapp_business')

          create(:ticket, customer: user, group_id: channel.group_id, state_id: Ticket::State.find_by(name: ticket_state).id, preferences: { channel_id: channel.id })
        end

        before { setup }

        context 'when ticket is open' do
          it 'does not create a new ticket' do
            expect { described_class.process(data:, callback_url_uuid:) }.not_to change(Ticket, :count)
          end
        end

        context 'when ticket is closed' do
          let(:ticket_state) { 'closed' }

          it 'creates a new ticket' do
            expect { described_class.process(data:, callback_url_uuid:) }.to change(Ticket, :count).by(1)
          end
        end
      end
    end
  end
end