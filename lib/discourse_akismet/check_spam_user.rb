module DiscourseAkismet
  class CheckSpamUser

    def initialize(user, profile_content)
      @user = user
      @profile_content = profile_content
    end

    def check_for_spam
      return unless should_check_for_spam?

      DiscourseAkismet.with_client do |client|
        move_to_state(client.comment_check(args) ? DiscourseAkismet::NEEDS_REVIEW : DiscourseAkismet::CHECKED)
      end
    end

    def should_check_for_spam?
      return false if @user.blank? || !SiteSetting.akismet_enabled? || SiteSetting.akismet_api_key.blank?

      return false if @user.trust_level != TrustLevel[0]

      return false if @profile_content.blank?

      true
    end

    def self.to_check
      User.where(trust_level: 0).where.not(id: UserCustomField.where(name: DiscourseAkismet::AKISMET_STATE_KEY).select(:user_id))
    end

    private

    def self.enqueue_user_for_spam_check(user_profile)
      Jobs.enqueue(:check_akismet_user, user_id: user_profile.user_id, profile_content: user_profile.bio_raw) if DiscourseAkismet::CheckSpamUser.new(user_profile.user, user_profile.bio_raw).should_check_for_spam?
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
        extra_args[:comment_author_email] = @user&.email
      end

      extra_args
    end

    def move_to_state(state)
      return unless should_check_for_spam?

      @user.upsert_custom_fields(DiscourseAkismet::AKISMET_STATE_KEY => state)
    end

  end
end
