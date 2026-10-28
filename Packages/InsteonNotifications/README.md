# InsteonNotifications

Let people know when their devices do something they care about.

- `NotificationRule`, `NotificationRuleID` and `NotificationTrigger`: what someone wants to hear about: an event a device profile names, such as a leak sensor turning wet, a group command, such as a switch turned on from its paddle, or a sensor going quiet, with a cooldown so a busy device doesn't notify on every pass
- `NotificationRuleSet`: checks device events and silent devices against a home's rules
- `DeviceNotification`: a rule that fired, for the app to deliver, such as with a push notification or an email

See the DocC catalog in `Sources/InsteonNotifications/InsteonNotifications.docc` for the full documentation.
