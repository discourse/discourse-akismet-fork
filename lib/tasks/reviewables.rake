desc 'Migrate akismet reviews to the new Reviewable API'
task 'reviewables:migrate_akismet_reviews' => :environment do
  reporter = Discourse.system_user

  migrate_reviewables
  migrate_creation_history
  migrate_resolution_history
end

def migrate_reviewables
  reporter = Discourse.system_user
  DB.exec <<~SQL
    INSERT INTO reviewables(
      type,
      status,
      created_by_id,
      reviewable_by_moderator,
      payload,
      category_id,
      topic_id,
      potential_spam,
      target_id,
      target_type,
      target_created_by_id,
      created_at,
      updated_at
    )
    SELECT
      'ReviewableAkismetPost',
      CASE
        WHEN uh.custom_type = 'confirmed_spam_deleted' THEN #{Reviewable.statuses[:deleted]}
        WHEN pcf.value = 'confirmed_spam' THEN #{Reviewable.statuses[:approved]}
        WHEN pcf.value = 'confirmed_ham' THEN #{Reviewable.statuses[:rejected]}
        WHEN pcf.value = 'dismissed' THEN #{Reviewable.statuses[:ignored]}
        ELSE #{Reviewable.statuses[:pending]}
      END,
      #{reporter.id},
      TRUE,
      json_build_object(),
      t.category_id,
      p.topic_id,
      TRUE,
      pcf.post_id,
      'Post',
      p.user_id,
      pcf.created_at,
      pcf.updated_at
    FROM post_custom_fields AS pcf
    INNER JOIN posts AS p ON pcf.post_id = p.id
    INNER JOIN topics AS t ON t.id = p.topic_id
    LEFT JOIN user_histories AS uh ON uh.post_id = pcf.post_id AND uh.custom_type = 'confirmed_spam_deleted'
    WHERE
      pcf.name = 'AKISMET_STATE' AND
      pcf.value IN ('dismissed', 'needs_review', 'confirmed_spam', 'confirmed_ham')
  SQL
end

def migrate_creation_history
  DB.exec <<~SQL
    INSERT INTO reviewable_histories (
      reviewable_id,
      reviewable_history_type,
      status,
      created_by_id,
      created_at,
      updated_at
    )
    SELECT
      r.id,
      #{ReviewableHistory.types[:created]},
      #{Reviewable.statuses[:ignored]},
      r.created_by_id,
      r.created_at,
      r.created_at
    FROM reviewables AS r
    WHERE r.type = 'ReviewableAkismetPost'
  SQL
end

def migrate_resolution_history
  DB.exec <<~SQL
    INSERT INTO reviewable_histories (
      reviewable_id,
      reviewable_history_type,
      status,
      created_by_id,
      created_at,
      updated_at
    )
    SELECT
      r.id,
      #{ReviewableHistory.types[:transitioned]},
      CASE
        WHEN uh.custom_type = 'confirmed_spam_deleted' THEN #{Reviewable.statuses[:deleted]}
        WHEN uh.custom_type = 'confirmed_spam' THEN #{Reviewable.statuses[:approved]}
        WHEN uh.custom_type = 'confirmed_ham' THEN #{Reviewable.statuses[:rejected]}
        ELSE #{Reviewable.statuses[:ignored]}
      END,
      uh.acting_user_id,
      r.updated_at,
      r.updated_at
    FROM reviewables AS r
    INNER JOIN user_histories AS uh ON uh.post_id = r.target_id
    WHERE
      uh.custom_type IN ('confirmed_spam', 'confirmed_ham', 'dismissed', 'confirmed_spam_deleted') AND
      r.type = 'ReviewableAkismetPost'
  SQL
end
