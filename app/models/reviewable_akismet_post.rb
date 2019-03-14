class ReviewableAkismetPost < Reviewable
  def build_actions(actions, guardian, _args)
    build_action(actions, :confirm_spam, icon: 'check')
    build_action(actions, :not_spam, icon: 'thumbs-up')
    build_action(actions, :dismiss, icon: 'times')
    build_action(actions, :confirm_delete, icon: 'trash-alt') if guardian.is_staff?
  end

  # Reviewable#perform should be used instead of these action methods.
  # These are only part of the public API because #perform needs them to be public.

  def perform_confirm_spam(performed_by, _args)
    DiscourseAkismet.move_to_state(target, 'confirmed_spam')
    log_confirmation(performed_by, 'confirmed_spam')

    successful_transition :approved
  end

  def perform_not_spam(performed_by, _args)
    Jobs.enqueue(:update_akismet_status, post_id: target_id, status: 'ham')
    DiscourseAkismet.move_to_state(target, 'confirmed_ham')
    log_confirmation(performed_by, 'confirmed_ham')

    PostDestroyer.new(performed_by, target).recover if target.deleted_at

    successful_transition :rejected
  end

  def perform_dismiss(performed_by, _args)
    DiscourseAkismet.move_to_state(target, 'dismissed')
    log_confirmation(performed_by, 'dismissed')

    successful_transition :ignored
  end

  def perform_confirm_delete(performed_by, _args)
    DiscourseAkismet.move_to_state(target, 'confirmed_spam')
    log_confirmation(performed_by, 'confirmed_spam_deleted')

    if Guardian.new(performed_by).can_delete_user?(target.user)
      UserDestroyer.new(performed_by).destroy(target.user, user_deletion_opts(performed_by))
    end

    successful_transition :deleted
  end

  private

  def successful_transition(to_state)
    create_result(:success, to_state)  { |result| result.recalculate_score = true }
  end

  def build_action(actions, id, icon:, bundle: nil, client_action: nil, confirm: false)
    actions.add(id, bundle: bundle) do |action|
      prefix = "js.akismet.#{id}"
      action.icon = icon
      action.label = "#{prefix}"
      action.client_action = client_action
      action.confirm_message = "#{prefix}.confirm" if confirm
    end
  end

  def user_deletion_opts(performed_by)
    base = {
      context: I18n.t('akismet.delete_reason', performed_by: performed_by.username),
      delete_posts: true
    }

    base.tap do |b|
      b.merge!(block_email: true, block_ip: true) if Rails.env.production?
    end
  end

  def log_confirmation(performed_by, custom_type)
    topic = target.topic || Topic.with_deleted.find(target.topic_id)

    StaffActionLogger.new(performed_by).log_custom(custom_type,
      post_id: target.id,
      topic_id: topic.id,
      created_at: target.created_at
    )
  end
end
