class MigrateDismissedCustomLogs < ActiveRecord::Migration[5.2]
  def up
    DB.exec <<~SQL
      UPDATE user_histories
      SET custom_type = 'ignored'
      WHERE custom_type = 'dismissed' AND action = #{UserHistory.actions[:custom_staff]}
    SQL
  end

  def down
    DB.exec <<~SQL
      UPDATE user_histories
      SET custom_type = 'dimissed'
      WHERE custom_type = 'ignored' AND action = #{UserHistory.actions[:custom_staff]}
    SQL
  end
end
