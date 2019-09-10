# frozen_string_literal: true

require_dependency 'reviewable'

class ReviewableAkismetUser < Reviewable
  def build_actions(actions, guardian, _args)
    return [] unless pending?

    build_action(actions, :not_spam, icon: 'thumbs-up')
    build_action(actions, :reject_user_delete, icon: 'trash-alt', confirm: true) if guardian.is_staff?
  end

  # Reviewable#perform should be used instead of these action methods.
  # These are only part of the public API because #perform needs them to be public.

  def perform_not_spam(performed_by, _args)
    bouncer.submit_feedback(target, 'ham')
    log_confirmation(performed_by, 'confirmed_ham')

    successful_transition :rejected, :disagreed
  end

  def perform_reject_user_delete(performed_by, _args)
    if target && Guardian.new(performed_by).can_delete_user?(target)
      log_confirmation(performed_by, 'confirmed_spam_deleted')
      bouncer.submit_feedback(target, 'spam')
      Jobs.enqueue(
        :confirm_akismet_flagged_posts,
        user_id: target.id, performed_by_id: performed_by.id
      )
      UserDestroyer.new(performed_by).destroy(target, user_deletion_opts(performed_by))
    end

    successful_transition :deleted, :agreed, recalculate_score: false
  end

  private

  def bouncer
    DiscourseAkismet::UsersBouncer.new
  end

  def successful_transition(to_state, update_flag_status, recalculate_score: true)
    create_result(:success, to_state)  do |result|
      result.recalculate_score = recalculate_score
      result.update_flag_stats = { status: update_flag_status, user_ids: [created_by_id] }
    end
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
      delete_posts: true,
      delete_as_spammer: true,
      quiet: true
    }

    base.tap do |b|
      b.merge!(block_email: true, block_ip: true) if Rails.env.production?
    end
  end

  def log_confirmation(performed_by, custom_type)
    StaffActionLogger.new(performed_by).log_custom(custom_type)
  end

  def post; end
end
