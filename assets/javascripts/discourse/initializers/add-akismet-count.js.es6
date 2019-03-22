import { withPluginApi } from "discourse/lib/plugin-api";

function attachAkismetReviewCount(api) {
  api.addFlagProperty("currentUser.akismet_review_count");
  api.decorateWidget("hamburger-menu:admin-links", dec => {
    return dec.attach("link", {
      route: "adminPlugins.akismet",
      label: "akismet.title",
      badgeCount: "akismet_review_count",
      badgeClass: "flagged-posts"
    });
  });
};

function subscribeToReviewCount(messageBus, user) {
  messageBus.subscribe("/akismet_counts", function(result) {
    if (result) {
      user.set("akismet_review_count", result.akismet_review_count || 0);
    };
  });
};

export default {
  name: "add-akismet-count",
  before: "register-discourse-location",
  after: "inject-objects",

  initialize(container) {
    const site = container.lookup("site:main");
    if (!site.get("reviewable_api_enabled")) {
      const user = container.lookup("current-user:main");
      if (user && user.get("staff")) {
        
        withPluginApi("0.4", attachAkismetReviewCount);

        const messageBus = container.lookup("message-bus:main");
        subscribeToReviewCount(messageBus, user);
      };
    };
  }
};
