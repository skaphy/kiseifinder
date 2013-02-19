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

		# SECTION_TIME以上時間の空いたpostを探す
		# * 最新のpostが現在時刻より3時間より前: 最新のpost一件を配列にして返す
		# * 見つかった場合: 3時間以上空く直前のpostを返す
		# (12:30,15:00,15:10みたいになっていたら12:30からのpostを返す)
		# * 見つけられなかった場合: nil
		def find_posts
			allposts = @twitter.user_timeline(@screen_name, :count => 200)
			return [allposts.first] if allposts.first.created_at < Time.now-SECTION_TIME
			# 3時間以上時間を置いてされたpostを探す
			previous_created_at = allposts.first.created_at
			posts = allposts[1..-1]
			found = nil
			16.times do |x|
				posts.length.times do |i|
					post = posts[i]
					if (previous_created_at-post.created_at).to_i > SECTION_TIME
						found = i+(x*200)
						break
					end
					previous_created_at = post.created_at
				end
				# 3時間置いてからされたpostがあればループを抜ける
				break if found
				# そうでなければ15回目のループの時以外user_timelineを取得
				if x < 15
					posts = @twitter.user_timeline(@screen_name, :count => 200, :max_id => posts.last.id)
					allposts.concat(posts)
				end
			end
			return nil unless found
			allposts[0, found+2]
		end
		private :find_posts

		def get_latest_section_posts(allposts)
			# secstartはセクション開始となるpostのallposts上の位置
			# 3時間以上時間を空けてからされたpostから最新のpostに向けて
			# セクション内にされた最後のpostの次のpostの位置をsecstartにいれる
			# これで現在のセクションの開始時間がわかる
			secstart = allposts.length-1
			secstart.downto(0) do |i|
				if allposts[i].created_at-allposts[secstart].created_at > SECTION_TIME
					secstart = i
				end
			end
			allposts[0, secstart]
		end
		private :get_latest_section_posts

		def reset
			# XXX: あとで説明書きなおす
			# 過去3200post以内に3時間以上postされなかった時を探す
			allposts = find_posts
			if allposts && allposts.length == 1
				# 最新のpostが3時間より前
				# 次のpostの投稿時刻がセクション開始時刻になる
				@newsection = true
			elsif allposts && allposts.length > 1
				# 見つかった
				# 現在のセクションの開始時刻とpost数を取得
				secposts = get_latest_section_posts(allposts)
				@section_start = secposts.last.created_at
				@post_count = secposts.length
				@logger.info("#{@screen_name}: Reset section #{@post_count} #{@section_start} to #{section_end}")
			else
				# 過去3200postに3時間以上の空きを見つけられなかった
				# 現在規制中と仮定し、SECTION_MAXpost前のpostを前回のセクション開始とする
				section_post = posts[SECTION_MAX-1]
				@section_start = section_post.created_at
				@post_count = SECTION_MAX
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

		# postprocessにProcを渡しその中で規制リプライしたり、コマンド処理したりする。
		@postprocess = options[:postprocess]

		@preprocess = options[:preprocess]
		unless @preprocess
			# preprocessが指定されていなければデフォルトでフォロー中のユーザのみ対象とする
			@preprocess = Proc.new do |tweet|
				true
			end
		end

		@users={}
	end

	def self.start(options={})
		self.new(options).start
	end
	def start
		@stream.userstream do |status|
			if status.text
				screen_name = status.user.screen_name

				# 対象postでなければ何もしない
				next unless @preprocess.call(status)

				# 起動してから初めての投稿であればAccountのオブジェクトを作る
				@users[screen_name] = Account.new(screen_name, @client) unless @users[screen_name]

				# section_startが確定していない場合リセット
				@users[screen_name].reset unless @users[screen_name].section_start

				@users[screen_name].newpost(status.created_at)
				@postprocess.call(@client, status, @users[status.user.screen_name]) if @postprocess
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
		#:preprocess => ,
		:postprocess => Proc.new do |twitter, tweet, account|
			puts "@#{account.screen_name} #{account.post_count} #{account.section_end}"
		end
	)
end

