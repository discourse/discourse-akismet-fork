require 'rails_helper'

describe Jobs::CollectAkismetFeedback do
  before do
    SiteSetting.akismet_api_key = 'not_a_real_key'
    SiteSetting.akismet_enabled = true
  end

  let(:spam_reporter) { Fabricate(:admin) }
  let(:post) do
    Fabricate(:post).tap { |p| DiscourseAkismet.move_to_state(p, 'needs_review') }
  end

  it 'Does not collect Akismet feedback when the review is pending, ignored, or deleted' do
    ReviewableFlaggedPost.needs_review!(target: post, topic: post.topic, created_by: spam_reporter)

    Jobs.expects(:enqueue).never
    DiscourseAkismet.expects(:move_to_state).never

    described_class.new.execute({})
  end

  it 'Changes post and enqueues a job to submit feedback to Akismet when reviewable is accepted' do
    review = ReviewableFlaggedPost.needs_review!(target: post, topic: post.topic, created_by: spam_reporter)
    review.perform(spam_reporter, :agree_and_keep)

    Jobs.expects(:enqueue).with(:update_akismet_status, post_id: post.id, status: 'ham')
    DiscourseAkismet.expects(:move_to_state).with(post, 'confirmed_ham')

    described_class.new.execute({})
  end

  it 'Only changes post state to confirmed_spam but does not submit feedback to Akismet' do
    review = ReviewableFlaggedPost.needs_review!(target: post, topic: post.topic, created_by: spam_reporter)
    review.perform(spam_reporter, :disagree)

    Jobs.expects(:enqueue).never
    DiscourseAkismet.expects(:move_to_state).with(post, 'confirmed_spam')

    described_class.new.execute({})
  end
end
