# frozen_string_literal: true

module DiscourseAkismet
  class Bouncer
    VALID_STATUSES = %w[spam ham]
    VALID_STATES = %W[spam checked skipped new]
    AKISMET_STATE = 'AKISMET_STATE'

    def submit_feedback(target, status)
      raise Discourse::InvalidParameters.new(:status) unless VALID_STATUSES.include?(status)
      feedback = args_for(target)

      Jobs.enqueue(:update_akismet_status, feedback: feedback, status: status)
    end

    def move_to_state(target, state)
      return if target.blank? || SiteSetting.akismet_api_key.blank? || !VALID_STATES.include?(state)
      target.upsert_custom_fields(AKISMET_STATE => state)
    end

    def perform_check(client, target)
      pre_check_passed = before_check(target)

      if pre_check_passed
        client.comment_check(args_for(target)).tap do |spam_detected|
          spam_detected ? mark_as_spam(target) : mark_as_clear(target)
        end
      else
        move_to_state(target, 'skipped')
      end
    end

    def enqueue_for_check(target)
      if should_check?(target)
        move_to_state(target, 'new')
        enqueue_job(target)
      else
        move_to_state(target, 'skipped')
      end
    end

    protected

    def add_score(reviewable, reason)
      reviewable.add_score(
        spam_reporter, PostActionType.types[:spam],
        created_at: reviewable.created_at, reason: reason
      )
    end

    def spam_reporter
      @spam_reporter ||= Discourse.system_user
    end
  end
end
