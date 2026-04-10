<script>
import { mapGetters } from 'vuex';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';

export default {
  components: {
    ChatList,
    ConversationBox,
    CmdBarConversationSnooze,
    SidepanelSwitch,
    ConversationSidebar,
  },
  beforeRouteLeave(to, from, next) {
    // Clear selected state if navigating away from a conversation to a route without a conversationId to prevent stale data issues
    // and resolves timing issues during navigation with conversation view and other screens
    if (this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
    next(); // Continue with navigation
  },
  props: {
    inboxId: {
      type: [String, Number],
      default: 0,
    },
    conversationId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    teamId: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
  },
  setup() {
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();

    return {
      uiSettings,
      updateUISettings,
      accountId,
    };
  },
  data() {
    return {
      showSearchModal: false,
      workspaceBadgeLabel: 'Waterwair Chatagent',
      workspaceHeading: 'Customer operations workspace',
    };
  },
  computed: {
    ...mapGetters({
      chatList: 'getAllConversations',
      currentChat: 'getSelectedChat',
    }),
    showConversationList() {
      return this.isOnExpandedLayout ? !this.conversationId : true;
    },
    showMessageView() {
      return this.conversationId ? true : !this.isOnExpandedLayout;
    },
    isOnExpandedLayout() {
      const {
        LAYOUT_TYPES: { CONDENSED },
      } = wootConstants;
      const { conversation_display_type: conversationDisplayType = CONDENSED } =
        this.uiSettings;
      return conversationDisplayType !== CONDENSED;
    },

    shouldShowSidebar() {
      if (!this.currentChat.id) {
        return false;
      }

      const { is_contact_sidebar_open: isContactSidebarOpen } = this.uiSettings;
      return isContactSidebarOpen;
    },
    workspaceSummary() {
      if (this.currentChat?.meta?.sender?.name) {
        return `Live handoff thread for ${this.currentChat.meta.sender.name}`;
      }

      return 'Live handoff thread with routing, context, and customer history in one place.';
    },
    workspaceChips() {
      return [
        {
          label: 'Status',
          value: this.currentChat?.status || 'open',
        },
        {
          label: 'Priority',
          value: this.currentChat?.priority || 'normal',
        },
        {
          label: 'Team',
          value: this.currentChat?.meta?.team?.name || 'Frontline',
        },
      ];
    },
  },
  watch: {
    conversationId() {
      this.fetchConversationIfUnavailable();
    },
  },

  created() {
    // Clear selected state early if no conversation is selected
    // This prevents child components from accessing stale data
    // and resolves timing issues during navigation
    // with conversation view and other screens
    if (!this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
  },

  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('portals/index');
    this.initialize();
    this.$watch('$store.state.route', () => this.initialize());
    this.$watch('chatList.length', () => {
      this.setActiveChat();
    });
  },

  methods: {
    onConversationLoad() {
      this.fetchConversationIfUnavailable();
    },
    initialize() {
      this.$store.dispatch('setActiveInbox', this.inboxId);
      this.setActiveChat();
    },
    toggleConversationLayout() {
      const { LAYOUT_TYPES } = wootConstants;
      const {
        conversation_display_type:
          conversationDisplayType = LAYOUT_TYPES.CONDENSED,
      } = this.uiSettings;
      const newViewType =
        conversationDisplayType === LAYOUT_TYPES.CONDENSED
          ? LAYOUT_TYPES.EXPANDED
          : LAYOUT_TYPES.CONDENSED;
      this.updateUISettings({
        conversation_display_type: newViewType,
        previously_used_conversation_display_type: newViewType,
      });
    },
    fetchConversationIfUnavailable() {
      if (!this.conversationId) {
        return;
      }
      const chat = this.findConversation();
      if (!chat) {
        this.$store.dispatch('getConversation', this.conversationId);
      }
    },
    findConversation() {
      const conversationId = parseInt(this.conversationId, 10);
      const [chat] = this.chatList.filter(c => c.id === conversationId);
      return chat;
    },
    setActiveChat() {
      if (this.conversationId) {
        const selectedConversation = this.findConversation();
        // If conversation doesn't exist or selected conversation is same as the active
        // conversation, don't set active conversation.
        if (
          !selectedConversation ||
          selectedConversation.id === this.currentChat.id
        ) {
          return;
        }
        const { messageId } = this.$route.query;
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
          });
      } else {
        this.$store.dispatch('clearSelectedState');
      }
    },
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
  },
};
</script>

<template>
  <section class="flex w-full h-full min-w-0 gap-3 p-3 bg-transparent">
    <div class="flex min-w-0 flex-1 flex-col gap-3">
      <div
        class="rounded-2xl border border-[rgba(52,242,210,0.14)] bg-[radial-gradient(circle_at_top_left,rgba(52,242,210,0.18),transparent_34%),linear-gradient(180deg,rgba(255,255,255,0.04),rgba(255,255,255,0.02))] px-4 py-4"
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
              {{ workspaceSummary }}
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <div
              v-for="chip in workspaceChips"
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
      <div class="flex min-w-0 flex-1 gap-3">
        <div
          class="min-w-0 h-full rounded-2xl border border-n-weak bg-n-solid-2/80 overflow-hidden backdrop-blur-sm"
        >
          <ChatList
            :show-conversation-list="showConversationList"
            :conversation-inbox="inboxId"
            :label="label"
            :team-id="teamId"
            :conversation-type="conversationType"
            :folders-id="foldersId"
            :is-on-expanded-layout="isOnExpandedLayout"
            @conversation-load="onConversationLoad"
          />
        </div>
        <div
          v-if="showMessageView"
          class="flex flex-1 min-w-0 h-full rounded-2xl border border-n-weak bg-n-solid-2/85 overflow-hidden backdrop-blur-sm"
        >
          <ConversationBox
            :inbox-id="inboxId"
            :is-on-expanded-layout="isOnExpandedLayout"
          >
            <SidepanelSwitch v-if="currentChat.id" />
          </ConversationBox>
        </div>
        <div
          v-if="shouldShowSidebar"
          class="h-full rounded-2xl border border-n-weak bg-n-solid-2/85 overflow-hidden backdrop-blur-sm"
        >
          <ConversationSidebar :current-chat="currentChat" />
        </div>
      </div>
    </div>
    <CmdBarConversationSnooze />
  </section>
</template>
