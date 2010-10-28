require 'cinch'


class Watchman
	include Cinch::Plugin

	prefix ''
	match ".help", { :method => :help }
	match ".add mailbox", { :method => :add_mailbox }
	match ".fetch", { :method => :fetch }
    match /^([[A-z0-9]|[-_]]+):?/, { :method => :send }
    match /.+/, { :method => :update }
	match ".destroy", { :method => :destroy }
	match /\.last .+/, { :method => :last }

	AFK_SEC 	= 1 # Num of seconds before a user is considered AFK
	AFK_LINES 	=  50 # Num of lines before a user is considered AFK
	@@should_init = true

	# Initialize the plugin when the first require for a mailbox is made
	def init
		if @@should_init
			bot.logger.debug "initializing"
			@@should_init 	= false
			@users 			= Users.reload
		end
	end

	def help(m)
		m.reply "I'll track msgs that are sent to you when you're away for 30+ minutes or 50+ lines have scrolled by since you last spoke"
		m.reply ".add mailbox - adds a mailbox for your username"
		m.reply ".fetch - retrieves unread mail for your mailbox"
		m.reply ".destroy - blows away your mailbox"
		m.reply ".last [username] - the last time I saw this user was..."
	end

    # create a new mailbox
	def add_mailbox(m)
		init
		nick = m.user.nick
		if Mailbox.exists? nick
            m.reply "Mailbox already exists"
        else
			@users[nick] = User.new(nick)
            m.reply "Added a mailbox for #{nick}"
        end
    end


    # fetch a users mail
	def fetch(m)
		nick 		= m.user.nick
		user = @users[nick]
		bot.logger.debug "Inbox empty? #{user.mailbox.empty?}"
		bot.logger.debug "Temp empty? #{user.mailbox.temp_mailbox_empty?}"

        if user.mailbox.empty? && user.mailbox.temp_mailbox_empty?
            m.reply "No new mail"
        else
            m.reply "Unread mail (#{user.mailbox.size + user.mailbox.temp_mailbox_size}):"
			user.mailbox.temp_mailbox.each { |msg| m.reply "From #{msg.user}: #{msg.message}" }
			user.mailbox.mailbox.each { |msg| m.reply "From #{msg.user}: #{msg.message}" }
			user.mailbox.empty_mailboxes
        end
    end


    # add to mailbox if user hasn't been seen for x minutes
	def send(m)
		#nick = m.message[/^[[A-z0-9]|[-_]]+/]
		nick = m.message[/^.[^ :]+/]
		bot.logger.debug "Nick: #{nick}"
		user = @users[nick]
		if Mailbox.exists? nick
		    if user.is_afk?
				#user.mailbox.temp_mailbox.each { |msg| user.mailbox.send_to_inbox msg }
				#user.mailbox.empty_temp_mailbox
				user.mailbox.send_to_inbox m
				m.reply "-.-"
		    else
			    # User hasn't be inactive long enough, so put this msg into the temp queue
				user.mailbox.send_to_temp m
		    end
	    end
    end


    # Updates the last time the user said something, 
    # and the number of lines that have scrolled by since the user last said something
	def update(m)
		nick = m.user.nick
		user = @users[nick]
		if Mailbox.exists? nick
			user.just_saw

			# Empty the users temp queue since they just spoke
			user.mailbox.empty_temp_mailbox
		end

		@users.each do |box_user, val|

			# With every msg, check whether any mailbox users have msgs in their temp queue
			# that should be moved into their mailbox since they've been away so long
			if @users[box_user].is_afk?
				@users[box_user].mailbox.temp_mailbox.each { |msg| user.mailbox.send_to_inbox msg }
				@users[box_user].mailbox.empty_temp_mailbox
			end

			if box_user == nick
				@users[box_user].missed_lines = 0
			end
			@users[box_user].missed_lines += 1
		end
	end

    # Deletes a users mailbox
	def destroy m
		@users[m.user.nick].destroy
        m.reply "boom!"
    end

	# Prints the last time a registered user was seen
	def last(m)
		nick = m.message.split(/\W/)[2]
		user = @users[nick]
		if Mailbox.exists? nick
		    m.reply "Last saw #{nick} [ #{"%.2f" % ((Time.now - user.last_seen) / 60 / 60)} hrs | #{user.missed_lines} lines ] ago"
	    end
    end

	private #-------


	class Users

		def self.reload
			@@users = {}
			Dir["*.box"].each do |mailbox|
				nick = mailbox[0..-5]
				@@users[nick] =  User.new(nick)
			end
			@@users
		end

		def self.users
			@@users
		end

		def self.destroy user
			@@users.delete(user)
		end
	end

	class User

		attr_accessor :missed_lines, :last_seen

		def initialize nick
			@nick 			= nick
			@last_seen 		= Time.now # timestamp of when the user last said something
			@missed_lines 	= 0 # records the # of lines since the user last said something
			@mailbox 		= Mailbox.new @nick
			self
		end

		def mailbox
			@mailbox
		end

		def is_afk?
			(Time.now - @last_seen) >= AFK_SEC || @missed_lines >= AFK_LINES
		end

		# Updates the timestamp for when we last saw this user active
		def just_saw
			@last_seen = Time.now
		end

		def destroy
			mailbox.destroy
			Users.destroy(@nick)
		end
	end

	class Mailbox

		def initialize nick
			@nick 	  = nick
			@temp_box = [] # Holds msgs directed at a user who has been idle for < 30 mins || < 50 lines.
						   # This temp queue gets whiped if the user speakers within that time frame, otherwise
						   # the msgs are added to their inbox
			create_or_load_mailbox
		end

		def create_or_load_mailbox
			if has_mailbox?
				reload_mailbox
			else
				create_mailbox
			end
		end

		def destroy
			f = get_mailbox
			f.delete
			@temp_box = nil
		end

		# Adds the given message to the temp box
		def send_to_temp m
			@temp_box << m
		end

		def send_to_inbox m
			#f = get_mailbox
			#begin
			#	msgs = File.open("#{@nick}.box") { |f| Marshal.load(f) }
			#rescue EOFError
			#	msgs = []
			#end
			#msgs = []
			#msgs << m
			#File.open("#{@nick}.box", "w+") { |f| Marshal.dump(msgs, f) }
			File.open("#{@nick}.box", 'w+') { |f| Marshal.dump(m, f) }
			#f.close
		end

		# Determines if the user has a mailbox
		def self.exists? nick
			File.exists? "#{nick}.box"
			#(@mailboxes[nick] == nil) ? false : true
		end

		# Determines if the user has a mailbox
		def has_mailbox?
			File.exists? "#{@nick}.box"
			#(@mailboxes[nick] == nil) ? false : true
		end

		# Returns the temp box as an array
		def temp_mailbox
			@temp_box
		end

		# Returns the mailbox as an array
		def mailbox
			Marshal.load(get_mailbox)
			#msgs = []
			#get_mailbox.each { |l| msgs << l.chomp }
			#msgs
		end

		# Empties box the temp and inboxes
		def empty_mailboxes
			empty_mailbox
			empty_temp_mailbox
		end

		def empty_mailbox
			f = File.open("#{@nick}.box", "w")
			f.puts ""
			f.close
		end

		def empty_temp_mailbox
			@temp_box = []
		end

		def get_mailbox
			File.open("#{@nick}.box", "a+")
		end

		def empty?
			(get_mailbox.size == 0) ? true : false
		end

		def temp_mailbox_empty?
			@temp_box.empty?
		end

		def size
			get_mailbox.count
		end

		def temp_mailbox_size
			@temp_box.size
		end


		private #-------

		def create_mailbox
			`touch #{@nick}.box` # File.new is broken on this box :(
		end

		def reload_mailbox
			# nothing to do...
		end

	end

end


bot = Cinch::Bot.new do
    configure do |c|
		c.plugins.plugins = [Watchman]
		c.server = "irc.oftc.net"
		c.user = "watchman"
		c.nick = "watchman"
		#c.channels = ["#sharpiez", "#orb@work", "#irlab"]
		c.channels = ["#sharpiez"]
    end
end

bot.start
