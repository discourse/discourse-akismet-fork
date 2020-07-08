# frozen_string_literal: true

module DiscourseAkismet
  class UsersBouncer < Bouncer

    def self.to_check
      User
        .joins('INNER JOIN user_custom_fields ucf ON  users.id = ucf.user_id')
        .where(trust_level: TrustLevel[0])
        .where('ucf.name = ?', AKISMET_STATE)
        .where("ucf.value = 'new' OR (ucf.value = 'skipped' AND users.created_at > ?)", 1.day.ago)
    end

    def should_check?(user)
      SiteSetting.akismet_review_users? && super(user)
    end

    def suspect?(user)
      user.trust_level === TrustLevel[0] &&
        user.user_profile.bio_raw.present? &&
        user.user_auth_token_logs&.last&.client_ip.present?
    end

    private

    def enqueue_job(user)
      Jobs.enqueue(:check_users_for_spam, user_id: user.id)
    end

    def before_check(user)
      should_check?(user)
    end

    def mark_as_spam(user)
      reviewable = ReviewableAkismetUser.needs_review!(
        target: user, reviewable_by_moderator: true,
        created_by: spam_reporter,
        payload: { username: user.username, name: user.name, email: user.email, bio: user.user_profile.bio_raw }
      )

      add_score(reviewable, 'akismet_spam_user')
      move_to_state(user, 'confirmed_spam')
    end

    def mark_as_errored(user, reason)
      super do 
        ReviewableAkismetUser.needs_review!(
          target: user, reviewable_by_moderator: true,
          created_by: spam_reporter,
          payload: { username: user.username, name: user.name, email: user.email, bio: user.user_profile.bio_raw, external_error: reason }
        )
      end
    end

    def args_for(user)
      profile = user.user_profile
      token = user.user_auth_token_logs.last

      extra_args = {
        content_type: 'signup',
        permalink: "#{Discourse.base_url}/u/#{user.username_lower}",
        comment_author: user.username,
        comment_content: profile.bio_raw,
        comment_author_url: profile.website,
        user_ip: token.client_ip.to_s,
        user_agent: token.user_agent
      }

      # Sending the email to akismet is optional
      if SiteSetting.akismet_transmit_email?
        extra_args[:comment_author_email] = user.email
      end

      extra_args
    end
  end
end
