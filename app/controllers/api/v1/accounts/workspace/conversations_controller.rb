# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::Workspace::ConversationsController < Api::V1::Accounts::BaseController
  include DateRangeHelper

  before_action :set_conversation, only: [:show, :reply, :handoff, :closeout]

  def index
    result = ConversationFinder.new(Current.user, params).perform
    conversations = result[:conversations]

    render json: {
      workspace: workspace_payload,
      summary: workspace_summary_payload(result[:count]),
      conversations: conversations.map { |conversation| workspace_conversation_payload(conversation) },
      data: {
        meta: workspace_counts_payload(result[:count]),
        payload: conversations.map { |conversation| workspace_conversation_payload(conversation) }
      }
    }
  end

  def show
    render json: workspace_conversation_payload(@conversation, include_messages: true).merge(
      workspace: workspace_payload
    )
  end

  def reply
    message = Messages::MessageBuilder.new(Current.user, @conversation, reply_params).perform

    render json: {
      ok: true,
      reply: workspace_message_payload(message),
      conversation: workspace_conversation_payload(@conversation.reload, include_messages: true)
    }
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def handoff
    @conversation.update!(workspace_update_params)
    @conversation.update_labels(workspace_labels) if params.key?(:labels)
    merge_custom_attributes!(workspace_custom_attributes)

    render json: {
      ok: true,
      conversation: workspace_conversation_payload(@conversation.reload, include_messages: true)
    }
  end

  def closeout
    closeout_updates = {}
    closeout_updates[:status] = closeout_params[:status].presence || 'resolved'
    closeout_updates[:priority] = closeout_params[:priority] if closeout_params[:priority].present?
    closeout_updates[:snoozed_until] = parsed_snoozed_until if parsed_snoozed_until

    @conversation.update!(closeout_updates)
    @conversation.update_labels(workspace_labels) if params.key?(:labels)
    merge_custom_attributes!(closeout_custom_attributes)

    render json: {
      ok: true,
      conversation: workspace_conversation_payload(@conversation.reload, include_messages: true)
    }
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:id])
    authorize @conversation, :show?
  end

  def reply_params
    params.permit(:content, :private, :content_type, content_attributes: {})
  end

  def workspace_params
    @workspace_params ||= params.permit(
      :status,
      :priority,
      :team_id,
      :assignee_id,
      :snoozed_until,
      labels: [],
      custom_attributes: {}
    )
  end

  def closeout_params
    @closeout_params ||= params.permit(
      :status,
      :priority,
      :snoozed_until,
      :resolution_reason,
      :owner_summary,
      :follow_up_needed,
      labels: [],
      custom_attributes: {}
    )
  end

  # rubocop:disable Metrics/AbcSize
  def workspace_update_params
    updates = {}
    updates[:status] = workspace_params[:status] if workspace_params[:status].present?
    updates[:priority] = workspace_params[:priority] if workspace_params[:priority].present?
    updates[:team_id] = workspace_params[:team_id] if params.key?(:team_id)
    updates[:assignee_id] = workspace_params[:assignee_id] if params.key?(:assignee_id)
    updates[:snoozed_until] = parsed_snoozed_until if parsed_snoozed_until || params.key?(:snoozed_until)
    updates
  end
  # rubocop:enable Metrics/AbcSize

  def parsed_snoozed_until
    return nil if workspace_params[:snoozed_until].blank? && closeout_params[:snoozed_until].blank?

    parse_date_time(workspace_params[:snoozed_until].presence || closeout_params[:snoozed_until].to_s)
  end

  def workspace_labels
    Array(workspace_params[:labels].presence || closeout_params[:labels]).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def workspace_custom_attributes
    normalize_custom_attributes(workspace_params[:custom_attributes])
  end

  def closeout_custom_attributes
    direct_closeout = {
      resolution_reason: closeout_params[:resolution_reason],
      owner_summary: closeout_params[:owner_summary],
      follow_up_needed: closeout_params[:follow_up_needed]
    }.compact

    extra_attributes = normalize_custom_attributes(closeout_params[:custom_attributes])

    direct_closeout.merge(extra_attributes)
  end

  def merge_custom_attributes!(new_attributes)
    return if new_attributes.blank?

    merged_attributes = (@conversation.custom_attributes || {}).merge(new_attributes)
    @conversation.update!(custom_attributes: merged_attributes)
  end

  def normalize_custom_attributes(raw_attributes)
    return {} if raw_attributes.blank?

    if raw_attributes.is_a?(ActionController::Parameters)
      raw_attributes.to_unsafe_h
    else
      raw_attributes.to_h
    end
  end

  def workspace_payload
    config = GlobalConfig.get('INSTALLATION_NAME', 'BRAND_NAME', 'LOGO_THUMBNAIL')

    {
      name: config['INSTALLATION_NAME'],
      brand: config['BRAND_NAME'],
      logo_thumbnail: config['LOGO_THUMBNAIL'],
      account: {
        id: Current.account.id,
        name: Current.account.name
      }
    }
  end

  def workspace_summary_payload(total_count)
    {
      count: total_count[:all_count] || 0,
      mine_count: total_count[:mine_count] || 0,
      assigned_count: total_count[:assigned_count] || 0,
      unassigned_count: total_count[:unassigned_count] || 0
    }
  end

  def workspace_counts_payload(total_count)
    {
      mine_count: total_count[:mine_count] || 0,
      assigned_count: total_count[:assigned_count] || 0,
      unassigned_count: total_count[:unassigned_count] || 0,
      all_count: total_count[:all_count] || 0
    }
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
  def workspace_conversation_payload(conversation, include_messages: false)
    payload = {
      id: conversation.display_id,
      display_id: conversation.display_id,
      account_id: conversation.account_id,
      uuid: conversation.uuid,
      status: conversation.status,
      priority: conversation.priority,
      inbox_id: conversation.inbox_id,
      inbox: workspace_inbox_payload(conversation),
      contact: workspace_contact_payload(conversation),
      assignee: workspace_assignee_payload(conversation),
      team: workspace_team_payload(conversation),
      meta: workspace_meta_payload(conversation),
      labels: conversation.cached_label_list_array,
      unread_count: conversation.unread_incoming_messages.count,
      created_at: conversation.created_at.to_i,
      updated_at: conversation.updated_at.to_f,
      timestamp: conversation.last_activity_at.to_i,
      last_activity_at: conversation.last_activity_at.to_i,
      waiting_since: conversation.waiting_since&.to_i,
      snoozed_until: conversation.snoozed_until&.to_i,
      can_reply: conversation.can_reply?,
      muted: conversation.muted?,
      custom_attributes: conversation.custom_attributes || {},
      additional_attributes: conversation.additional_attributes || {},
      last_non_activity_message: conversation.messages
                                             .where(account_id: conversation.account_id)
                                             .non_activity_messages
                                             .first
                                             &.push_event_data
    }

    payload[:messages] = conversation.messages.includes(:sender).last(40).map { |message| workspace_message_payload(message) } if include_messages
    payload
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

  def workspace_inbox_payload(conversation)
    {
      id: conversation.inbox_id,
      name: conversation.inbox.name,
      channel_type: conversation.inbox.channel_type
    }
  end

  def workspace_contact_payload(conversation)
    {
      id: conversation.contact.id,
      name: conversation.contact.name,
      email: conversation.contact.email,
      phone_number: conversation.contact.phone_number,
      thumbnail: conversation.contact.avatar_url
    }
  end

  def workspace_assignee_payload(conversation)
    return nil unless conversation.assignee

    {
      id: conversation.assignee.id,
      name: conversation.assignee.name,
      email: conversation.assignee.email
    }
  end

  def workspace_team_payload(conversation)
    return nil unless conversation.team

    {
      id: conversation.team.id,
      name: conversation.team.name
    }
  end

  def workspace_meta_payload(conversation)
    payload = {
      sender: workspace_contact_payload(conversation),
      channel: conversation.inbox.channel_type,
      hmac_verified: conversation.contact_inbox&.hmac_verified
    }

    payload[:assignee] = workspace_assignee_payload(conversation) if conversation.assignee
    payload[:assignee_type] = conversation.assignee.class.name if conversation.assignee
    payload[:team] = workspace_team_payload(conversation) if conversation.team
    payload
  end

  def workspace_message_payload(message)
    {
      id: message.id,
      content: message.content,
      message_type: message.message_type,
      private: message.private,
      created_at: message.created_at.to_i,
      sender: workspace_message_sender_payload(message)
    }
  end

  def workspace_message_sender_payload(message)
    return nil unless message.sender

    {
      id: message.sender.id,
      name: message.sender.try(:name),
      type: message.sender.class.name
    }
  end
end
# rubocop:enable Metrics/ClassLength
