# frozen_string_literal: true

module Jobs
  class CleanOldAkismetCustomFields < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.akismet_enabled?

      DiscourseAkismet::PostsBouncer.new.clean_old_akismet_custom_fields
    end
  end
end
