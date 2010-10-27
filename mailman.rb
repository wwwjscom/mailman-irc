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

	AFK_SEC 	= 1800 # Num of seconds before a user is considered AFK
	AFK_LINES 	=  50 # Num of lines before a user is considered AFK
	@@should_init = true

	# Initialize the plugin when the first require for a mailbox is made
	def init
		if @@should_init
			bot.logger.debug "initializing"
			@@should_init 	= false
			@users 			= Users.reload
			@mailboxes 		= {}
			@last_seen 		= {} # timestamp of when the user last said something
			@missed_lines 	= {} # records the # of lines since the user last said something
			@temp_queue 	= {} # Holds msgs directed at a user who has been idle for < 30 mins || < 50 lines.
								 # This temp queue gets whiped if the user speakers within that time frame, otherwise
								 # the msgs are added to their inbox
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
			#@mailboxes[nick] = Mailbox.new(nick)
			#@mailboxes[nick] 	= []
			#@temp_queue[nick] 	= []
			#@last_seen[nick] 	= Time.now
			#@missed_lines[nick] = 0
            m.reply "Added a mailbox for #{nick}"
        end
    end


    # fetch a users mail
	def fetch(m)
		#mailbox		= load_mailbox nick
		#mail		= get_mailbox nick
		#temp_mail 	= get_temp_mailbox nick
        #mail 		= @mailboxes[nick]
		#temp_mail 	= @temp_queue[nick]

		nick 		= m.user.nick
		user = @users[nick]

        if user.mailbox.empty? && user.mailbox.temp_mailbox_empty?
            m.reply "No new mail"
        else
            m.reply "Unread mail (#{user.mailbox.size + user.mailbox.temp_mailbox_size}):"
			user.mailbox.temp_mailbox.each { |msg| m.reply "From #{msg.user}: #{msg.message}" }
			user.mailbox.mailbox.each { |msg| m.reply "From #{msg.user}: #{msg.message}" }
			user.mailbox.empty_mailboxes
			#temp_mail.each { |msg| m.reply "From #{msg.user}: #{msg.message}" }
            #mail.each { |msg| m.reply "From #{msg.user}: #{msg.message}" }
			#empty_boxes nick
        end
    end


    # add to mailbox if user hasn't been seen for x minutes
	def send(m)
		nick = m.message[/^[[A-z0-9]|[-_]]+/]
		user = @users[nick]
		if Mailbox.exists? nick
		    if user.is_afk?
				user.mailbox.temp_mailbox.each { |msg| user.mailbox.send_to_inbox msg }
				user.mailbox.empty_temp_mailbox
				user.mailbox.send_to_inbox m
				#@temp_queue.each { |msg| send_to_mailbox nick, msg }
				#empty_temp_box nick
				#send_to_mailbox nick, m
				m.reply "-.-"
		    else
			    # User hasn't be inactive long enough, so put this msg into the temp queue
				#send_to_temp_mailbox nick, m
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
			#empty_temp_box nick
			user.mailbox.empty_temp_mailbox
		end

		@users.each do |box_user, val|

			# With every msg, check whether any mailbox users have msgs in their temp queue
			# that should be moved into their mailbox since they've been away so long
			if @users[box_user].is_afk?
				@users[box_user].mailbox.temp_mailbox.each { |msg| user.mailbox.send_to_inbox msg }
				@users[box_user].mailbox.empty_temp_mailbox
				#@temp_queue[box_user].each { |msg| send_to_mailbox box_user, msg }
				#empty_temp_box box_user
			end

			if box_user == nick
				@users[box_user].missed_lines = 0
				#@missed_lines[box_user] = 0
			end
			@users[box_user].missed_lines += 1
			#@missed_lines[box_user] += 1
		end
	end

    # Deletes a users mailbox
	def destroy m
		@users[m.user.nick].destroy
        #@mailboxes[m.user.nick] = nil
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
			@last_seen 		= Time.now
			@missed_lines 	= 0
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
			@nick = nick
			@temp_box = []
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
			f = get_mailbox
			f.puts m
			f.close
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
			msgs = []
			get_mailbox.each { |l| msgs << l }
			msgs
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
			File.open("#{@nick}.box", "w+")
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

	def load_mailbox nick
		if @mailboxes[nick] != nil
			return @mailboxes[nick]
		else
			return Mailbox.new(nick)
		end
	end

	def send_to_mailbox nick, msg
		@mailboxes[nick] << msg
	end

	def send_to_temp_mailbox nick, msg
		@temp_queue[nick] << msg
	end



	def temp_mailbox_empty? nick
		get_temp_mailbox(nick).empty?
	end

	def mailbox_size
	end



	def is_afk? nick
		(Time.now - @last_seen[nick]) >= AFK_SEC || @missed_lines[nick] >= AFK_LINES
	end

	def empty_boxes nick
		empty_temp_box nick
		empty_box nick
	end

	def empty_temp_box nick
		@temp_queue[nick] = []
	end

	def empty_box nick
		@mailboxes[nick] = []
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
