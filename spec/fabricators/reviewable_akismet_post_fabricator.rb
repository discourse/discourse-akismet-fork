# frozen_string_literal: true

Fabricator(:reviewable_akismet_post) do
  reviewable_by_moderator true
  type 'ReviewableAkismetPost'
  created_by { Discourse.system_user }
  topic
  target_type 'Post'
  target { Fabricate(:post) }
end

Fabricator(:reviewable_akismet_user) do
  reviewable_by_moderator true
  type 'ReviewableAkismetUser'
  created_by { Discourse.system_user }
  target_type 'User'
  target do
    Fabricate(:user, trust_level: TrustLevel[0]).tap do |user|
      user.user_profile.bio_raw = "I am batman"
      user.user_auth_token_logs = [UserAuthTokenLog.new(client_ip: '127.0.0.1', action: 'an_action')]
    end
  end
end
