<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useTrack } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { INBOX_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';

import InboxItemHeader from './components/InboxItemHeader.vue';
import ConversationBox from 'dashboard/components/widgets/conversation/ConversationBox.vue';
import InboxEmptyState from './InboxEmptyState.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { uiSettings } = useUISettings();

const isConversationLoading = ref(false);

const notification = useMapGetter('notifications/getFilteredNotifications');
const currentChat = useMapGetter('getSelectedChat');
const conversationById = useMapGetter('getConversationById');
const uiFlags = useMapGetter('notifications/getUIFlags');
const meta = useMapGetter('notifications/getMeta');

const inboxId = computed(() => Number(route.params.inboxId));
const conversationId = computed(() => Number(route.params.id));

const activeSortOrder = computed(() => {
  const { inbox_filter_by: filterBy = {} } = uiSettings.value;
  const { sort_by: sortBy } = filterBy;
  return sortBy || 'desc';
});

const notifications = computed(() => {
  return notification.value({
    sortOrder: activeSortOrder.value,
  });
});

const activeNotification = computed(() => {
  return notifications.value?.find(
    n => n.primary_actor?.id === conversationId.value
  );
});

const totalNotificationCount = computed(() => {
  return meta.value.count;
});

const queueInsight = computed(() => {
  const contactName = currentChat.value?.meta?.sender?.name;
  if (contactName) {
    return `Focused handoff lane for ${contactName}`;
  }
  return 'Focused handoff lane for escalations, follow-up, and revenue-critical conversations';
});
const workspaceBadgeLabel = 'Waterwair Chatagent';
const workspaceHeading = 'Handoff queue';

const queueChips = computed(() => {
  const stats = [
    {
      label: 'Queue',
      value: `${totalNotificationCount.value || 0} live`,
    },
    {
      label: 'Status',
      value: currentChat.value?.status || 'open',
    },
    {
      label: 'Owner',
      value:
        currentChat.value?.meta?.assignee?.name ||
        currentChat.value?.assignee?.name ||
        'Unassigned',
    },
  ];

  return stats;
});

const showEmptyState = computed(() => {
  return (
    !conversationId.value ||
    (!notifications.value?.length && uiFlags.value.isFetching)
  );
});

const activeNotificationIndex = computed(() => {
  return notifications.value?.findIndex(
    n => n.primary_actor?.id === conversationId.value
  );
});

const isContactPanelOpen = computed(() => {
  if (currentChat.value.id) {
    const { is_contact_sidebar_open: isContactSidebarOpen } = uiSettings.value;
    return isContactSidebarOpen;
  }
  return false;
});

const findConversation = () => {
  return conversationById.value(conversationId.value);
};

const openNotification = async notificationItem => {
  const {
    id,
    primary_actor_id: primaryActorId,
    primary_actor_type: primaryActorType,
    primary_actor: {
      meta: { unreadCount } = {},
      id: conversationIdFromNotification,
    },
    notification_type: notificationType,
  } = notificationItem;

  useTrack(INBOX_EVENTS.OPEN_CONVERSATION_VIA_INBOX, {
    notificationType,
  });

  try {
    await store.dispatch('notifications/read', {
      id,
      primaryActorId,
      primaryActorType,
      unreadCount,
    });

    router.push({
      name: 'inbox_view_conversation',
      params: { type: 'conversation', id: conversationIdFromNotification },
    });
  } catch {
    // error
  }
};

const setActiveChat = async () => {
  const selectedConversation = findConversation();
  if (!selectedConversation) return;

  try {
    await store.dispatch('setActiveChat', { data: selectedConversation });
    emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
  } catch {
    // error
  }
};

const fetchConversationById = async () => {
  if (!conversationId.value) return;

  store.dispatch('clearSelectedState');
  const existingChat = findConversation();

  if (existingChat) {
    await setActiveChat();
    return;
  }

  isConversationLoading.value = true;

  try {
    await store.dispatch('getConversation', conversationId.value);
    await setActiveChat();
  } catch {
    // error
  } finally {
    isConversationLoading.value = false;
  }
};

const navigateToConversation = (activeIndex, direction) => {
  const isValidPrev = direction === 'prev' && activeIndex > 0;
  const isValidNext =
    direction === 'next' && activeIndex < totalNotificationCount.value - 1;

  if (!isValidPrev && !isValidNext) return;

  const updatedIndex = direction === 'prev' ? activeIndex - 1 : activeIndex + 1;
  const targetNotification = notifications.value[updatedIndex];

  if (targetNotification) {
    openNotification(targetNotification);
  }
};

const onClickNext = () => {
  navigateToConversation(activeNotificationIndex.value, 'next');
};

const onClickPrev = () => {
  navigateToConversation(activeNotificationIndex.value, 'prev');
};

watch(
  conversationId,
  (newVal, oldVal) => {
    if (newVal !== oldVal) {
      fetchConversationById();
    }
  },
  { immediate: true }
);

onMounted(async () => {
  await store.dispatch('agents/get');
});
</script>

<template>
  <div class="h-full w-full flex-1 p-3">
    <div v-if="showEmptyState" class="flex w-full h-full">
      <InboxEmptyState
        :empty-state-message="$t('INBOX.LIST.NO_MESSAGES_AVAILABLE')"
      />
    </div>
    <div
      v-else
      class="flex flex-col w-full h-full rounded-2xl border border-n-weak bg-n-solid-2/85 overflow-hidden backdrop-blur-sm"
    >
      <div
        class="mx-3 mt-3 rounded-2xl border border-[rgba(52,242,210,0.14)] bg-[radial-gradient(circle_at_top_left,rgba(52,242,210,0.16),transparent_32%),linear-gradient(180deg,rgba(255,255,255,0.04),rgba(255,255,255,0.02))] px-4 py-4"
      >
        <div
          class="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between"
        >
          <div class="min-w-0">
            <div
              class="mb-2 inline-flex rounded-full border border-[rgba(52,242,210,0.18)] bg-[rgba(52,242,210,0.08)] px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-n-slate-11"
            >
              {{ workspaceBadgeLabel }}
            </div>
            <div class="text-lg font-semibold text-n-slate-12">
              {{ workspaceHeading }}
            </div>
            <div class="mt-1 text-sm text-n-slate-10">
              {{ queueInsight }}
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <div
              v-for="chip in queueChips"
              :key="chip.label"
              class="min-w-[7rem] rounded-2xl border border-white/5 bg-black/10 px-3 py-2"
            >
              <div
                class="text-[11px] uppercase tracking-[0.14em] text-n-slate-9"
              >
                {{ chip.label }}
              </div>
              <div class="mt-1 text-sm font-medium capitalize text-n-slate-12">
                {{ chip.value }}
              </div>
            </div>
          </div>
        </div>
      </div>
      <InboxItemHeader
        :total-length="totalNotificationCount"
        :current-index="activeNotificationIndex"
        :active-notification="activeNotification"
        @next="onClickNext"
        @prev="onClickPrev"
      />
      <div
        v-if="isConversationLoading"
        class="flex items-center flex-1 my-4 justify-center bg-n-solid-1"
      >
        <Spinner class="text-n-brand" />
      </div>
      <div v-else class="flex h-[calc(100%-13rem)] min-w-0">
        <ConversationBox
          class="flex-1 [&.conversation-details-wrap]:!border-0"
          is-inbox-view
          :inbox-id="inboxId"
          :is-on-expanded-layout="false"
        >
          <SidepanelSwitch v-if="currentChat.id" />
        </ConversationBox>
        <ConversationSidebar
          v-if="isContactPanelOpen"
          :current-chat="currentChat"
        />
      </div>
    </div>
  </div>
</template>
