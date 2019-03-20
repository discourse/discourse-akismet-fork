Fabricator(:reviewable_akismet_post) do
  reviewable_by_moderator true
  type 'ReviewableAkismetPost'
  created_by { Fabricate(:user) }
  topic
  target_type 'Post'
  target { Fabricate(:post) }
end
