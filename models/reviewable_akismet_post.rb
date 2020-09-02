# frozen_string_literal: true

require_dependency 'reviewable'

class ReviewableAkismetPost < Reviewable
  def self.action_aliases
    { confirm_suspend: :confirm_spam }
  end

  def build_actions(actions, guardian, _args)
    return [] unless pending?

    agree = actions.add_bundle("#{id}-agree", icon: 'thumbs-up', label: 'reviewables.actions.agree.title')

    build_action(actions, :confirm_spam, icon: 'check', bundle: agree)

    if guardian.can_suspend?(target_created_by)
      build_action(actions, :confirm_suspend, icon: 'ban', bundle: agree, client_action: 'suspend')
    end

    if guardian.can_delete_user?(target_created_by)
      build_action(actions, :confirm_delete, icon: 'trash-alt', bundle: agree, confirm: true)
    end

    build_action(actions, :not_spam, icon: 'thumbs-down')
    build_action(actions, :ignore, icon: 'external-link-alt')
  end

  def post
    @post ||= (target || Post.with_deleted.find_by(id: target_id))
  end

  # Reviewable#perform should be used instead of these action methods.
  # These are only part of the public API because #perform needs them to be public.

  def perform_confirm_spam(performed_by, _args)
    bouncer.submit_feedback(post, 'spam')
    log_confirmation(performed_by, 'confirmed_spam')

    # Double-check the original post is deleted
    PostDestroyer.new(performed_by, post).destroy unless post.deleted_at?

    successful_transition :approved, :agreed
  end

  def perform_not_spam(performed_by, _args)
    bouncer.submit_feedback(post, 'ham')
    log_confirmation(performed_by, 'confirmed_ham')

    PostDestroyer.new(performed_by, post).recover if post.deleted_at

    successful_transition :rejected, :disagreed
  end

  def perform_ignore(performed_by, _args)
    log_confirmation(performed_by, 'ignored')

    successful_transition :ignored, :ignored
  end

  def perform_confirm_delete(performed_by, _args)
    if Guardian.new(performed_by).can_delete_user?(target_created_by)
      bouncer.submit_feedback(post, 'spam')
      log_confirmation(performed_by, 'confirmed_spam_deleted')

      PostDestroyer.new(performed_by, post).destroy unless post.deleted_at?
      UserDestroyer.new(performed_by).destroy(target_created_by, user_deletion_opts(performed_by))
    end

    successful_transition :deleted, :agreed, recalculate_score: false
  end

  private

  def bouncer
    DiscourseAkismet::PostsBouncer.new
  end

  def successful_transition(to_state, update_flag_status, recalculate_score: true)
    create_result(:success, to_state)  do |result|
      result.recalculate_score = recalculate_score
      result.update_flag_stats = { status: update_flag_status, user_ids: [created_by_id] }
    end
  end

  def build_action(actions, id, icon:, bundle: nil, confirm: false, button_class: nil, client_action: nil)
    actions.add(id, bundle: bundle) do |action|
      action.icon = icon
      action.label = "js.akismet.#{id}"
      action.confirm_message = 'js.akismet.reviewable_delete_prompt' if confirm
      action.client_action = client_action
      action.button_class = button_class
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
      topic_id: post.topic_id
    )
  end
end
