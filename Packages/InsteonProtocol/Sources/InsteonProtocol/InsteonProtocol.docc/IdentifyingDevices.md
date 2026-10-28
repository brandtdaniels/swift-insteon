# Identifying Devices

Find out what kind of device is on the network.

## Overview

Every INSTEON device belongs to a device category (DevCat) and subcategory (SubCat), and runs a
particular firmware version. Devices report these themselves, so an app never needs to ask the
user what they installed.

### Asking a device who it is

Send ``StandardDirectCommand/idRequest`` and the device answers with a SET Button Pressed
broadcast, which ``SetButtonPressed`` reads. The same broadcast arrives when someone holds the
device's SET button to link it.

Devices that support ``StandardDirectCommand/productDataRequest`` answer it with an extended
message, which ``ProductData`` reads. Besides the category and subcategory, it carries the
device's ``ProductKey``, which the Developer's Guide requires of devices made after
February 1, 2007.

When the modem becomes a device's controller by linking, it reports the device's category and
subcategory in ``AllLinkingCompleted``. Only devices that don't answer the Product Data Request
report a firmware version there; the others send `0xFF`, which reads as `nil`.

### Looking a device up

Together, a device's category, subcategory and firmware version identify its product and the
firmware it runs. What a device can do depends on both, because commands can differ between
firmware versions of the same product, so that information belongs in one shared device
database that apps look devices up in, rather than in each app.
