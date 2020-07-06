# frozen_string_literal: true

require 'rails_helper'
require_relative '../fabricators/reviewable_akismet_post_fabricator.rb'

describe DiscourseAkismet::PostsBouncer do
  before do
    SiteSetting.akismet_api_key = 'not_a_real_key'
    SiteSetting.akismet_enabled = true
  end

  let(:post) { Fabricate(:post) }

  describe '#args_for' do
    before do
      post.upsert_custom_fields(
        'AKISMET_REFERRER' => 'https://discourse.org',
        'AKISMET_IP_ADDRESS' => '1.2.3.4',
        'AKISMET_USER_AGENT' => 'Discourse Agent'
      )
    end

    it "should return args for a post" do
      result = subject.args_for(post)
      expect(result[:content_type]).to eq('forum-post')
      expect(result[:permalink]).to be_present
      expect(result[:comment_content]).to be_present
      expect(result[:user_ip]).to eq('1.2.3.4')
      expect(result[:referrer]).to eq('https://discourse.org')
      expect(result[:user_agent]).to eq('Discourse Agent')
      expect(result[:comment_author]).to eq(post.user.username)
      expect(result[:comment_author_email]).to eq(post.user.email)
    end

    it "will omit email if the site setting is enabled" do
      SiteSetting.akismet_transmit_email = false
      result = subject.args_for(post)
      expect(result[:comment_author_email]).to be_blank
    end

    context "custom munge" do
      after do
        described_class.reset_munge
      end

      before do
        described_class.munge_args do |args|
          args[:comment_author] = "CUSTOM: #{args[:comment_author]}"
          args.delete(:user_agent)
        end
      end

      it "will munge the args before returning them" do
        result = subject.args_for(post)
        expect(result[:user_agent]).to be_blank
        expect(result[:comment_author]).to eq("CUSTOM: #{post.user.username}")

        described_class.reset_munge
        result = subject.args_for(post)
        expect(result[:user_agent]).to eq('Discourse Agent')
        expect(result[:comment_author]).to eq(post.user.username)
      end
    end
  end

  describe "custom fields" do
    before do
      subject.store_additional_information(
        post,
        ip_address: '1.2.3.5',
        referrer: 'https://eviltrout.com',
        user_agent: 'Discourse App',
       )

       subject.move_to_state(post, 'skipped')
    end

    it "custom fields can be attached and IPs anonymized" do
      expect(post.custom_fields['AKISMET_IP_ADDRESS']).to eq('1.2.3.5')
      expect(post.custom_fields['AKISMET_REFERRER']).to eq('https://eviltrout.com')
      expect(post.custom_fields['AKISMET_USER_AGENT']).to eq('Discourse App')

      UserAnonymizer.new(post.user, nil, anonymize_ip: '0.0.0.0').make_anonymous
      post.reload
      expect(post.custom_fields['AKISMET_IP_ADDRESS']).to eq('0.0.0.0')
    end
  end

  describe '#check_post' do
    let(:client) { Akismet::Client.build_client }

    after do
      clear_stubs
    end

    it 'Creates a new ReviewableAkismetPost when spam is confirmed by Akismet' do
      subject.move_to_state(post, 'new')

      stub_spam_confirmation

      subject.perform_check(client, post)
      reviewable_akismet_post = ReviewableAkismetPost.last

      expect(reviewable_akismet_post.status).to eq Reviewable.statuses[:pending]
      expect(reviewable_akismet_post.post).to eq post
      expect(reviewable_akismet_post.reviewable_by_moderator).to eq true
      expect(reviewable_akismet_post.payload['post_cooked']).to eq post.cooked

      # notifies user that post is hidden and includes post URL
      expect(Post.last.raw).to include(post.full_url)
      expect(Post.last.raw).to include(post.topic.title)
    end

    it 'Creates a new score for the new reviewable' do
      subject.move_to_state(post, 'new')

      stub_spam_confirmation

      subject.perform_check(client, post)
      reviewable_akismet_score = ReviewableScore.last

      expect(reviewable_akismet_score.user).to eq Discourse.system_user
      expect(reviewable_akismet_score.reviewable_score_type).to eq PostActionType.types[:spam]
      expect(reviewable_akismet_score.take_action_bonus).to be_zero
    end

    it 'Creates a new ReviewableAkismetPost when an API error is returned' do
      subject.move_to_state(post, 'new')

      stub_akismet_error

      subject.perform_check(client, post)
      reviewable_akismet_post = ReviewableAkismetPost.last

      expect(reviewable_akismet_post.status).to eq Reviewable.statuses[:pending]
      expect(reviewable_akismet_post.post).to eq post
      expect(reviewable_akismet_post.reviewable_by_moderator).to eq true
      expect(reviewable_akismet_post.payload['external_error']['error']).to eq('status')
      expect(reviewable_akismet_post.payload['external_error']['code']).to eq('123')
      expect(reviewable_akismet_post.payload['external_error']['msg']).to eq('An alert message')
    end

    def stub_spam_confirmation
      response = { status: 200, body: 'true' }

      Excon.defaults[:mock] = true
      Excon.stub({ host: /rest.akismet.com/ }, response)
    end

    def stub_akismet_error
      headers = { "X-akismet-error" => "status", "X-akismet-alert-code" => "123", "X-akismet-alert-msg" => "An alert message" }
      response = { status: 200, body: 'false', headers: headers }

      Excon.defaults[:mock] = true
      Excon.stub({ host: /rest.akismet.com/ }, response)
    end

    def clear_stubs
      Excon.stubs.clear
    end
  end

  describe "#to_check" do
    it 'retrieves posts waiting to be reviewed by Akismet' do
      subject.move_to_state(post, 'new')

      posts_to_check = described_class.to_check.map(&:post)

      expect(posts_to_check).to contain_exactly(post)
    end

    it 'does not retrieve posts that already had another reviewable queued post' do
      subject.move_to_state(post, 'new')
      ReviewableQueuedPost.needs_review!(target: post, created_by: Discourse.system_user)

      expect(described_class.to_check).to be_empty
    end
  end

  describe "#should_check?" do
    fab!(:post) { Fabricate(:post) }
    let(:user) { post.user }

    it { expect(subject.should_check?(nil)).to eq(false) }

    before do
      SiteSetting.skip_akismet_trust_level = TrustLevel[2]

      user.user_stat # Create user stat object

      post.raw = "More than 20 characters long"
      user.user_stat.post_count = 0
      user.trust_level = TrustLevel[1]
    end

    it 'returns true on the first post of a TL1 user' do
      expect(subject.should_check?(post)).to eq(true)
    end

    it 'returns false the topic was deleted' do
      post.topic.trash!

      expect(subject.should_check?(post.reload)).to eq(false)
    end

    it 'returns false when the topic is a private message' do
      post.topic.archetype = Archetype.private_message

      expect(subject.should_check?(post)).to eq(false)
    end

    it 'returns false the the post body is less than 20 chars long' do
      post.raw = 'Less than 20 chars'

      expect(subject.should_check?(post)).to eq(false)
    end

    it 'returns false when TL0+ users are skipped' do
      user.user_stat.post_count = 2
      SiteSetting.skip_akismet_trust_level = TrustLevel[0]

      expect(subject.should_check?(post)).to eq(false)
    end

    it 'returns false when users with 19+ posts are skipped' do
      user.user_stat.post_count = 20
      SiteSetting.skip_akismet_posts = 19

      expect(subject.should_check?(post)).to eq(false)
    end

    it 'returns false when post content is just an URI' do
      user.user_stat.post_count = 2
      post.raw = "https://testurl.test/test/akismet/96850311111131"

      expect(subject.should_check?(post)).to eq(false)
    end

    it 'returns false when the plugin is disabled' do
      SiteSetting.akismet_enabled = false

      expect(subject.should_check?(post)).to eq(false)
    end

    it 'returns false when a reviewable already exists' do
      Fabricate(:reviewable_akismet_post, target: post)

      expect(subject.should_check?(post)).to eq(false)
    end
  end
end
