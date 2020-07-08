# discourse-akismet

Official documentation at https://meta.discourse.org/t/discourse-akismet-anti-spam/109337

## Contributing

Help make this plugin better by submitting a PR.  It's as easy as 1-2-3.

* fork the repo
* create a feature branch
* rebase off master and send the pr

This project uses the MIT-LICENSE.

## Uninstallation

If you wish to uninstall this plugin permanently, you'll have to remove the objects it created **first**. You could do so by executing the following rake task:

`bundle exec rake akismet_uninstall:delete_reviewables`

:warning: THIS ACTION CANNOT BE UNDONE. BE SURE YOU REALLY WANT TO UNINSTALL THE PLUGIN :warning:

## Issues

If you have issues or suggestions for the plugin, please bring them up on [Discourse Meta](https://meta.discourse.org).

## Authors

The original plugin was authored by Michael Verdi (@verdi327) for use at New Relic. It has since been
forked and refactored by Robin Ward (@eviltrout) at Discourse.
