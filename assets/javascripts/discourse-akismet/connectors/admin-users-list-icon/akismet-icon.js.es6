export default {
  shouldRender(args) {
    return args.query === "suspect";
  },

  setupComponent(args, component) {
    const state = args.user.akismet_state;
    component.set("new", state === "new");
    component.set("skipped", state === "skipped");
    component.set("checked", state === "confirmed_ham");
    component.set("spam", state === "confirmed_spam");
  },
};
