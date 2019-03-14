require_dependency 'reviewable'

class ReviewableAkismetPost < Reviewable
  def build_actions(actions, guardian, _args)
    return [] unless pending?

    build_action(actions, :confirm_spam, icon: 'check')
    build_action(actions, :not_spam, icon: 'thumbs-up')
    build_action(actions, :ignore, icon: 'times')
    build_action(actions, :confirm_delete, icon: 'trash-alt', confirm: true) if guardian.is_staff?
  end

  def post
    @post ||= (target || Post.with_deleted.find_by(id: target_id))
  end

  # Reviewable#perform should be used instead of these action methods.
  # These are only part of the public API because #perform needs them to be public.

  def perform_confirm_spam(performed_by, _args)
    log_confirmation(performed_by, 'confirmed_spam')

    successful_transition :approved
  end

  def perform_not_spam(performed_by, _args)
    Jobs.enqueue(:update_akismet_status, post_id: target_id, status: 'ham')
    log_confirmation(performed_by, 'confirmed_ham')

    PostDestroyer.new(performed_by, target).recover if target.deleted_at

    successful_transition :rejected
  end

  def perform_ignore(performed_by, _args)
    log_confirmation(performed_by, 'ignored')

    successful_transition :ignored
  end

  def perform_confirm_delete(performed_by, _args)
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

  def build_action(actions, id, icon:, bundle: nil, confirm: false)
    actions.add(id, bundle: bundle) do |action|
      action.icon = icon
      action.label = "js.akismet.#{id}"
      action.confirm_message = 'js.akismet.reviewable_delete_prompt' if confirm
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
    StaffActionLogger.new(performed_by).log_custom(custom_type,
      post_id: post.id,
      topic_id: post.topic_id,
      created_at: target.created_at
    )
  end
end
