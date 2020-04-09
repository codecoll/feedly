# Feedly client for emacs

## Installation

In order to read your own feeds you need a developer API token for authorization. [You can get one here](https://developer.feedly.com/v3/developer/). When you have your token then set it with

    (setq feedly-access-token "your token")
    
If you use an incorrect token then **the secure connection will ask for a username/password which shouldn't happen.**

If you set the token then the you fetch your feeds with

    M-x feedly
