#!/usr/bin/ruby
# -*- coding: utf-8 -*-

# Based on http://ltzz.info/alpha/twitter_kisei.html

require 'pp'
require 'logger'
require 'rubygems'
require 'bundler/setup'
require 'twitter'
require 'tweetstream'

class KiseiFinder

	# 1セクションあたりの時間
	SECTION_TIME = 60*60*3

	# セクションあたりの最大投稿数
	SECTION_MAX = 127

	class Account

		attr_reader :screen_name

		# セクション開始時間
		attr_reader :section_start

		# セクション内での投稿数
		attr_reader :post_count

		def initialize(screen_name, twitter)
			@screen_name = screen_name
			@twitter = twitter
			@newsection = false
			@logger = Logger.new(STDOUT)
		end

		def section_start=(value)
			raise StandardError unless value.kind_of?(Time)
			@section_start = value
		end

		def start_new_section(time)
			@section_start = time
			@post_count = 1
		end

		def newpost(time)
			if @newsection
				# 新セクションの開始
				# ただしUserStreamはたまに変な値を送ってくるため注意
				# (本当は現在時刻から1分以内にされたもののみ許可とかにしたほうがいいと思う)
				start_new_section(time)
				@logger.info("#{@screen_name}: Start new section #{@section_start} to #{section_end}")
			elsif @section_start == nil or @post_count == nil
				# セクションの開始時刻がわからないか、投稿数がわからない
				#reset
				@logger.info("#{@screen_name}: section_start or post_count are unknown")
			elsif time >= @section_start and time <= section_end
				# セクション時間内のpost
				@post_count += 1
				@logger.info("#{@screen_name}: Post #{section_end}")
			elsif time > section_end
				# section_endより後のpost
				start_new_section(time)
				@logger.info("#{@screen_name}: Start new section (over section_end) #{@section_start} to #{section_end}")
			end
		end

		# セクション終了時間
		def section_end
			# セクション開始時間の3時間後
			@section_start+SECTION_TIME
		end

		# セクションの残り時間
		def remain_section
			section_end-Time.now
		end

		# セクションあたりの投速
		def post_speed
			post_count/(section_end-@section_start)
		end

		def reset
			posts = @twitter.user_timeline(@screen_name, :count => 3200)
			if posts[0].created_at < Time.now-SECTION_TIME
				# 最新のpostが3時間より前の場合次がセクション開始になる
				@newsection = true
			else
				# 3時間以上時間を置いてされたpostを探す
				previous_created_at = posts[0].created_at
				found = nil
				puts previous_created_at
				(1..posts.length-1).each do |i|
					post = posts[i]
					if (previous_created_at-post.created_at).to_i > SECTION_TIME
						found = i
						break
					end
					previous_created_at = post.created_at
				end
				if found
					# 見つけたので現在のセクションの開始時刻とpost数を取得
					@section_start = posts[found-1].created_at
					@post_count = found
					@logger.info("#{@screen_name}: Reset section #{@post_count} #{@section_start} to #{section_end}")
				else
					# 無いようであれば現在規制中と仮定し、SECTION_MAXpost前のpostを前回のセクション開始とする
					section_post = posts[126]
					@section_start = section_post.created_at
					@post_count = SECTION_MAX
				end
			end
		end

	end

	def initialize(options={})
		@client = Twitter::Client.new(
			:consumer_key => options[:consumer_key],
			:consumer_secret => options[:consumer_secret],
			:oauth_token => options[:access_token],
			:oauth_token_secret => options[:access_secret]
		)
		@stream = TweetStream::Client.new(
			:consumer_key => options[:consumer_key],
			:consumer_secret => options[:consumer_secret],
			:oauth_token => options[:access_token],
			:oauth_token_secret => options[:access_secret],
			:auth_method => :oauth
		)
		# after_postaddedにProcを渡しその中で規制リプライしたり、コマンド処理したりする。
		@after_postadded = options[:after_postadded]
		@users = {}
		options[:users].each do |screen_name|
			@users[screen_name] = Account.new(screen_name, @client)
			@users[screen_name].reset
		end
	end

	def self.start(options={})
		self.new(options).start
	end
	def start
		@stream.userstream do |status|
			if status.text and @users[status.user.screen_name]
				@users[status.user.screen_name].newpost(status.created_at)
				@after_postadded.call(@client, status, @users[status.user.screen_name]) if @after_postadded
			end
		end
	end

end

if $0 == __FILE__
	config = YAML.load(File.read("config.yaml"))
	KiseiFinder.start(
		:consumer_key => config["twitter"]["consumer_key"],
		:consumer_secret => config["twitter"]["consumer_secret"],
		:access_token => config["twitter"]["access_token"],
		:access_secret => config["twitter"]["access_secret"],
		:users => config["users"],
		:after_postadded => Proc.new do |twitter, tweet, account|
			puts "@#{account.screen_name} #{account.post_count}(#{account.post_speed.round}) #{account.section_end}"
		end
	)
end

