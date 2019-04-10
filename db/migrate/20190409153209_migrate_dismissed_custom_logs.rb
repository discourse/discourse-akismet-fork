class MigrateDismissedCustomLogs < ActiveRecord::Migration[5.2]
  def up
    DB.exec <<~SQL
      UPDATE user_histories AS uh
      SET custom_type = 'ignored'
      FROM post_custom_fields AS pcf
      WHERE 
        uh.custom_type = 'dismissed' AND 
        uh.action = #{UserHistory.actions[:custom_staff]} AND
        uh.post_id = pcf.post_id AND
        pcf.name = 'AKISMET_STATE' AND pcf.value = 'dismissed'
    SQL
  end

  def down
    DB.exec <<~SQL
      UPDATE user_histories AS uh
      SET custom_type = 'dimissed'
      FROM post_custom_fields AS pcf
      WHERE 
        uh.custom_type = 'ignored' AND 
        uh.action = #{UserHistory.actions[:custom_staff]} AND
        uh.post_id = pcf.post_id AND
        pcf.name = 'AKISMET_STATE' AND pcf.value = 'dismissed'
    SQL
  end
end
