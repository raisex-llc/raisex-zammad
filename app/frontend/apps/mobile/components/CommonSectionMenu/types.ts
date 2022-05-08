// Copyright (C) 2012-2022 Zammad Foundation, https://zammad-foundation.org/

import { type Props as LinkProps } from '@mobile/components/CommonSectionMenu/CommonSectionMenuLink.vue'

export type MenuItem = {
  type: 'link'
  onClick?(event: MouseEvent): void
} & LinkProps