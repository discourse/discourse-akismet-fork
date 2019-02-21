module DiscourseAkismet
  class CheckSpamUser

    def initialize(user, profile_content)
      @user = user
      @profile_content = profile_content
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

      return false if @profile_content.blank?

      true
    end

    def args
      extra_args = {
        content_type: 'user-tl0',
        permalink: "#{Discourse.base_url}/u/#{@user.username}",
        comment_author: @user.username,
        comment_content: @profile_content,
        user_ip: @user.custom_fields['AKISMET_IP_ADDRESS']
      }

      if SiteSetting.akismet_transmit_email?
        extra_args[:comment_author_email] = @user.try(:email)
      end

      extra_args
    end

    def move_to_state(state)
      return unless should_check_for_spam?

      @user.upsert_custom_fields(DiscourseAkismet::AKISMET_STATE_KEY => state)
    end

    def self.to_check
      ::User.where(trust_level: 0).where.not(id: UserCustomField.where(name: DiscourseAkismet::AKISMET_STATE_KEY).select(:user_id))
    end

  end
end
