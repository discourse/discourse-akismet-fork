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
        subject.reset_munge
      end

      before do
        subject.munge_args do |args|
          args[:comment_author] = "CUSTOM: #{args[:comment_author]}"
          args.delete(:user_agent)
        end
      end

      it "will munge the args before returning them" do
        result = subject.args_for(post)
        expect(result[:user_agent]).to be_blank
        expect(result[:comment_author]).to eq("CUSTOM: #{post.user.username}")

        subject.reset_munge
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

    it 'Creates a new ReviewableAkismetPost when spam is confirmed by Akismet' do
      subject.move_to_state(post, 'new')

      stub_spam_confirmation

      subject.perform_check(client, post)
      reviewable_akismet_post = ReviewableAkismetPost.last

      expect(reviewable_akismet_post.status).to eq Reviewable.statuses[:pending]
      expect(reviewable_akismet_post.post).to eq post
      expect(reviewable_akismet_post.reviewable_by_moderator).to eq true
      expect(reviewable_akismet_post.payload['post_cooked']).to eq post.cooked
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

    def stub_spam_confirmation
      stub_request(:post, /rest.akismet.com/).to_return(body: 'true')
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
end
