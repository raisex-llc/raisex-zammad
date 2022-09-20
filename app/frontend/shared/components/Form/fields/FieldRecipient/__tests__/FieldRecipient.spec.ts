// Copyright (C) 2012-2022 Zammad Foundation, https://zammad-foundation.org/

import { escapeRegExp } from 'lodash-es'
import { waitFor } from '@testing-library/vue'
import { FormKit } from '@formkit/vue'
import gql from 'graphql-tag'
import { renderComponent } from '@tests/support/components'
import { createMockClient } from 'mock-apollo-client'
import { provideApolloClient } from '@vue/apollo-composable'
import type { AutoCompleteOption } from '../../FieldAutoComplete/types'

const testOptions: AutoCompleteOption[] = [
  {
    value: 'baz@bar.tld',
    label: 'Baz',
    heading: 'baz@bar.tld',
  },
  {
    value: 'qux@bar.tld',
    label: 'Qux',
    heading: 'qux@bar.tld',
  },
  {
    value: 'corge@bar.tld',
    label: 'Corge',
    heading: 'corge@bar.tld',
  },
]

const AutocompleteSearchRecipientDocument = gql`
  query autocompleteSearchRecipient($query: String!, $limit: Int) {
    autocompleteSearchRecipient(query: $query, limit: $limit) {
      value
      label
      labelPlaceholder
      heading
      headingPlaceholder
      disabled
      icon
    }
  }
`

type AutocompleteSearchRecipientQuery = {
  __typename?: 'Queries'
  autocompleteSearchRecipient: Array<{
    __typename?: 'AutocompleteEntry'
    value: string
    label: string
    labelPlaceholder?: Array<string> | null
    heading?: string | null
    headingPlaceholder?: Array<string> | null
    disabled?: boolean | null
    icon?: string | null
  }>
}

const mockQueryResult = (
  query: string,
  limit: number,
): AutocompleteSearchRecipientQuery => {
  const options = testOptions.map((option) => ({
    ...option,
    labelPlaceholder: null,
    headingPlaceholder: null,
    disabled: null,
    icon: null,
    __typename: 'AutocompleteEntry',
  }))

  const deaccent = (s: string) =>
    s.normalize('NFD').replace(/[\u0300-\u036f]/g, '')

  // Trim and de-accent search keywords and compile them as a case-insensitive regex.
  //   Make sure to escape special regex characters!
  const filterRegex = new RegExp(escapeRegExp(deaccent(query)), 'i')

  // Search across options via their de-accented labels.
  const filteredOptions = options.filter(
    (option) =>
      filterRegex.test(deaccent(option.label)) ||
      filterRegex.test(deaccent(option.heading!)),
  ) as unknown as {
    __typename?: 'AutocompleteEntry'
    value: string
    label: string
    labelPlaceholder?: Array<string> | null
    heading?: string | null
    headingPlaceholder?: Array<string> | null
    disabled?: boolean | null
    icon?: string | null
  }[]

  return {
    autocompleteSearchRecipient: filteredOptions.slice(0, limit ?? 25),
  }
}

const mockClient = () => {
  const mockApolloClient = createMockClient()

  mockApolloClient.setRequestHandler(
    AutocompleteSearchRecipientDocument,
    (variables) => {
      return Promise.resolve({
        data: mockQueryResult(variables.query, variables.limit),
      })
    },
  )

  provideApolloClient(mockApolloClient)
}

const wrapperParameters = {
  form: true,
  formField: true,
  router: true,
  dialog: true,
  store: true,
}

const testProps = {
  type: 'recipient',
}

beforeAll(async () => {
  // So we don't need to wait until it loads inside test.
  await import('../../FieldAutoComplete/FieldAutoCompleteInputDialog.vue')
})

// We include only some query-related test cases, as the actual autocomplete component has its own unit test.
describe('Form - Field - Recipient - Features', () => {
  mockClient()

  it('supports selection of unknown values', async () => {
    const wrapper = renderComponent(FormKit, {
      ...wrapperParameters,
      props: {
        ...testProps,
        debounceInterval: 0,
      },
    })

    await wrapper.events.click(wrapper.getByRole('list'))

    const filterElement = wrapper.getByRole('searchbox')

    await wrapper.events.type(filterElement, 'foo@bar.tld')

    let selectOptions = wrapper.getAllByRole('option')

    expect(selectOptions).toHaveLength(1)
    expect(selectOptions[0]).toHaveTextContent('foo@bar.tld')

    wrapper.events.click(wrapper.getAllByRole('option')[0])

    await waitFor(() => {
      expect(wrapper.emitted().inputRaw).toBeTruthy()
    })

    const emittedInput = wrapper.emitted().inputRaw as Array<Array<InputEvent>>

    expect(emittedInput[0][0]).toBe('foo@bar.tld')
    expect(wrapper.getByRole('listitem')).toHaveTextContent('foo@bar.tld')

    await wrapper.events.click(wrapper.getByRole('list'))

    selectOptions = wrapper.getAllByRole('option')

    expect(selectOptions).toHaveLength(1)
    expect(selectOptions[0]).toHaveTextContent('foo@bar.tld')
  })

  it('supports validation of filter input', async () => {
    const wrapper = renderComponent(FormKit, {
      ...wrapperParameters,
      props: {
        ...testProps,
        debounceInterval: 0,
      },
    })

    await wrapper.events.click(wrapper.getByRole('list'))

    const filterElement = wrapper.getByRole('searchbox')

    await wrapper.events.type(filterElement, 'bar')

    expect(
      wrapper.queryByText('Please enter a valid email address.'),
    ).toBeInTheDocument()

    await wrapper.events.clear(filterElement)

    await wrapper.events.type(filterElement, 'foo@bar.tld')

    expect(
      wrapper.queryByText('Please enter a valid email address.'),
    ).not.toBeInTheDocument()

    const selectOptions = wrapper.getAllByRole('option')

    expect(selectOptions).toHaveLength(1)
    expect(selectOptions[0]).toHaveTextContent('foo@bar.tld')
  })
})
