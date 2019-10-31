export default {
  setupComponent(args, component) {
    const state = args.user.akismet_state;
    component.set("new", state === "new");
    component.set("skipped", state === "skipped");
    component.set("checked", state === "checked");
    component.set("spam", state === "spam");
  }
};
