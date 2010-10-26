#require 'cinch'
#
#class Hello
#  include Cinch::Plugin
#
#  match "hello"
#
#  def execute(m)
#    m.reply "Hello, #{m.user.nick}"
#  end
#end
#
#bot = Cinch::Bot.new do
#  configure do |c|
#    c.secure = true
#    c.user = "mailman"
#    c.nick = "mailman"
#    c.server = "irc.oftc.net"
#    c.channels = ["#sharpiez"]
#    c.plugins.plugins = [Hello]
#  end
#end
#
#bot.start


require 'cinch'

bot = Cinch::Bot.new do
    store = {}
    configure do |c|
        c.server = "irc.oftc.net"
        c.channels = ["#sharpiez"]
        store[:mailboxes] = {}
    end

    # create a new mailbox
    on :message, ".add mailbox" do |m|
        if store[:mailboxes][m.user.nick] != nil
            m.reply "Mailbox already exists"
        else
            store[:mailboxes][m.user.nick] = []
            m.reply "Added a mailbox for #{m.user.nick}"
        end
    end

    # fetch a users mail
    on :message, ".fetch" do |m|
        mail = store[:mailboxes][m.user.nick]
        if mail.size == 0
            m.reply "No new mail"
        else
            m.reply "Unread mail (#{mail.size}):"
            mail.each do |msg|
                m.reply "From #{msg.user}: #{msg.message}"
            end
            store[:mailboxes][m.user.nick] = []
        end
    end

    # add to mailbox
    on :message, /^([A-z0-9_]+):?/ do |m, user|
        mailboxes = store[:mailboxes]
        if mailboxes[user] != nil
            mailboxes[user] << m
            m.reply "stamped"
        end
    end

    # Deletes a users mailbox
    on :message, ".destroy" do |m|
        store[:mailboxes][m.user.nick] = nil
        m.reply "boom!"
    end

    on :message, ".help" do |m|
        m.reply ".add mailbox - adds a mailbox for your username"
        m.reply ".fetch - retrieves unread mail for your mailbox"
        m.reply ".destroy - blows away your mailbox"
    end

end

bot.start
