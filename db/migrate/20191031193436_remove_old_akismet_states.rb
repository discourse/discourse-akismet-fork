# frozen_string_literal: true

class RemoveOldAkismetStates < ActiveRecord::Migration[6.0]
  def up
    DB.exec(<<~SQL, updated_at: 5.minutes.ago
      DELETE FROM post_custom_fields
      WHERE name = 'AKISMET_STATE' AND value = 'needs_review' AND updated_at < :updated_at
    SQL
    )
  end

  def down
  end
end
