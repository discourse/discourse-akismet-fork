# frozen_string_literal: true

desc 'Delete reviewables and post custom fields created by this plugin'
task 'akismet_uninstall:delete_reviewables' => :environment do
  PostCustomField.where(name: DiscourseAkismet::Bouncer::AKISMET_STATE).delete_all

  delete_association(ReviewableScore)
  delete_association(ReviewableHistory)

  ReviewableAkismetPost.delete_all
  ReviewableAkismetUser.delete_all
end

def delete_association(klass)
  klass
    .joins(:reviewable)
    .where(reviewables: { type: %w[ReviewableAkismetPost ReviewableAkismetUser] })
    .delete_all
end
