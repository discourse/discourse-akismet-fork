module DiscourseAkismet
  class User

    def initialize(user)
      @user = user
    end

    def check_for_spam
      return unless should_check_for_spam?

      DiscourseAkismet.with_client do |client|
        if client.comment_check(args)
          move_to_state(DiscourseAkismet::NEEDS_REVIEW)
          # should we notify admin user for it?
        else
          move_to_state(DiscourseAkismet::CHECKED)
        end

      end
    end

    def should_check_for_spam?
      return false if @user.blank? || !SiteSetting.akismet_enabled? || SiteSetting.akismet_api_key.blank?

      return false if @user.trust_level != TrustLevel[0]

      return false if @user.custom_fields[DiscourseAkismet::AKISMET_STATE_KEY].present?

      return false if profile_content.blank?

      true
    end


    def args
      extra_args = {
        content_type: 'user-tl0',
        permalink: "#{Discourse.base_url}/u/#{@user.username}",
        comment_author: @user.username,
        comment_content: profile_content
      }

      if SiteSetting.akismet_transmit_email?
        extra_args[:comment_author_email] = @user.try(:email)
      end

      extra_args
    end

    def move_to_state(state)
      return unless should_check_for_spam?

      to_update = {
        DiscourseAkismet::AKISMET_STATE_KEY => state
      }

      @user.upsert_custom_fields(to_update)
    end

    def profile_content
      @user.user_profile.bio_raw || ''
    end

    def self.to_check
      ::User.where(trust_level: 0).where.not(id: UserCustomField.where(name: DiscourseAkismet::AKISMET_STATE_KEY).pluck(:user_id))
    end

  end
end
