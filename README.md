# Feedly client for Emacs

It's an Emacs client for your Feedly account. You can read your feeds and the read-state is synchronized back to the Feedly server.

## Installation

In order to read your own feeds you need a developer API token for authorization. [You can get one here](https://developer.feedly.com/v3/developer/). When you have your token then set it with

    (setq feedly-access-token "your token")
    
If you use an incorrect token then **the secure connection will ask for a username/password which shouldn't happen**, so if it happens then check your token again.

If you set the token then you can fetch your feeds with

    M-x feedly

## Usage

The current selection is marked with underline. The client was designed for keyboard control in mind. Here are the keys:

Key     |    Action
--------|-----------
`cursor up`   | move selection up
`cursor down`  | move selection down
`cursor right`   | expand current feed
`cursor left`  | collapse current feed
`return`  | show preview of selected feed item (press again to open it in your browser)
`a`  | mark all items in the current feed as read
`g`  | fetch new items from the server
`w`  | close item preview window and show only the item list
`s`  | mark all items in the current feed as read and then quit
`q`  | quit the Feedly buffer and restore window configuration



## Screenshot

![screenshot](https://raw.githubusercontent.com/codecoll/feedly/master/screenshot.PNG)
