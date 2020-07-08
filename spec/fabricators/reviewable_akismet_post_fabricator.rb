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
  target { Fabricate(:user) }
end
