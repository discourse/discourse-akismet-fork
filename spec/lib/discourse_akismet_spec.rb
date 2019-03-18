require 'rails_helper'

describe DiscourseAkismet do
  before do
    SiteSetting.akismet_api_key = 'not_a_real_key'
    SiteSetting.akismet_enabled = true
  end

  describe '#args_for_post' do
    let(:post) { Fabricate(:post) }

    before do
      post.upsert_custom_fields(
        'AKISMET_REFERRER' => 'https://discourse.org',
        'AKISMET_IP_ADDRESS' => '1.2.3.4',
        'AKISMET_USER_AGENT' => 'Discourse Agent'
      )
    end

    it "should return args for a post" do
      result = described_class.args_for_post(post)
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
      result = described_class.args_for_post(post)
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
        result = described_class.args_for_post(post)
        expect(result[:user_agent]).to be_blank
        expect(result[:comment_author]).to eq("CUSTOM: #{post.user.username}")

        described_class.reset_munge
        result = described_class.args_for_post(post)
        expect(result[:user_agent]).to eq('Discourse Agent')
        expect(result[:comment_author]).to eq(post.user.username)
      end
    end
  end

  describe "custom fields" do
    let(:post) { Fabricate(:post) }

    before do
      DiscourseAkismet.move_to_state(
        post,
        'skipped',
        ip_address: '1.2.3.5',
        referrer: 'https://eviltrout.com',
        user_agent: 'Discourse App',
      )
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

  describe '#check_for_spam', if: defined?(Reviewable) do
    it 'Creates a new ReviewableAkismetPost when spam is confirmed by Akismet' do
      post = Fabricate(:post)
      DiscourseAkismet.move_to_state(post, 'new')

      stub_spam_confirmation

      DiscourseAkismet.check_for_spam(post)
      reviewable_akismet_post = ReviewableAkismetPost.last

      expect(reviewable_akismet_post.status).to eq Reviewable.statuses[:pending]
      expect(reviewable_akismet_post.post).to eq post
      expect(reviewable_akismet_post.reviewable_by_moderator).to eq true
    end

    def stub_spam_confirmation
      stub_request(:post, /rest.akismet.com/).to_return(body: 'true')
    end
  end
end
