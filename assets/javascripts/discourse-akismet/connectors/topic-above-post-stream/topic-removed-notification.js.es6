export default {
  setupComponent(args, component) {
    const akismetDeletedTopicChannel = `/discourse-akismet/topic-deleted/${args.model.id}`;
    component.messageBus.subscribe(akismetDeletedTopicChannel, () => {
      component.set("akismetFlaggedTopic", true);
    });
  },
};
