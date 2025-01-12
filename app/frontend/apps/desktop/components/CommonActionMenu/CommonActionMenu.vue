<!-- Copyright (C) 2012-2024 Zammad Foundation, https://zammad-foundation.org/ -->

<script setup lang="ts">
import { computed, ref, toRefs } from 'vue'

import getUuid from '#shared/utils/getUuid.ts'
import type { ObjectLike } from '#shared/types/utils.ts'

import CommonPopover from '#desktop/components/CommonPopover/CommonPopover.vue'
import CommonButton from '#desktop/components/CommonButton/CommonButton.vue'
import CommonPopoverMenu from '#desktop/components/CommonPopover/CommonPopoverMenu.vue'
import { usePopover } from '#desktop/components/CommonPopover/usePopover.ts'
import type {
  ButtonSize,
  ButtonVariant,
} from '#desktop/components/CommonButton/types.ts'
import type {
  MenuItem,
  Orientation,
  Placement,
} from '#desktop/components/CommonPopover/types.ts'
import { usePopoverMenu } from '#desktop/components/CommonPopover/usePopoverMenu.ts'

interface Props {
  actions: MenuItem[]
  entity?: ObjectLike
  buttonSize?: ButtonSize
  buttonVariant?: ButtonVariant
  placement?: Placement
  orientation?: Orientation
  noSingleActionMode?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  buttonSize: 'large',
  buttonVariant: 'neutral',
  placement: 'start',
  orientation: 'autoVertical',
})

const popoverMenu = ref<InstanceType<typeof CommonPopoverMenu>>()

const { popover, isOpen: popoverIsOpen, popoverTarget, toggle } = usePopover()

const { actions, entity } = toRefs(props)
const { filteredMenuItems, singleMenuItemPresent, singleMenuItem } =
  usePopoverMenu(actions, entity, { provides: true })

const entityId = computed(() => props.entity?.id || getUuid())
const menuId = computed(() => `popover-${entityId.value}`)

const singleActionMode = computed(() => {
  if (props.noSingleActionMode) return false

  return singleMenuItemPresent.value
})
</script>

<template>
  <div v-if="filteredMenuItems" class="inline-block">
    <CommonButton
      v-if="singleActionMode"
      :size="buttonSize"
      :variant="buttonVariant"
      :aria-label="$t(singleMenuItem?.label)"
      :icon="singleMenuItem?.icon"
      @click="singleMenuItem?.onClick?.(entity as ObjectLike)"
    />
    <CommonButton
      v-else
      :id="entity?.id || entityId"
      ref="popoverTarget"
      :aria-label="$t('Action menu button')"
      aria-haspopup="true"
      :aria-controls="menuId"
      :class="{
        'outline outline-1 outline-offset-1 outline-blue-800': popoverIsOpen,
      }"
      :size="buttonSize"
      :variant="buttonVariant"
      icon="three-dots-vertical"
      @click="toggle"
    />

    <CommonPopover
      v-if="!singleActionMode"
      :id="menuId"
      ref="popover"
      :placement="placement"
      :orientation="orientation"
      :owner="popoverTarget"
    >
      <CommonPopoverMenu
        ref="popoverMenu"
        :entity="entity"
        :popover="popover"
      />
    </CommonPopover>
  </div>
</template>
