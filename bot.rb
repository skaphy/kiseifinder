#!/usr/bin/ruby
# -*- coding: utf-8 -*-

$stdout.sync = true
$stderr.sync = true

require 'yaml'
require 'logger'
require './kiseifinder'

class KiseiFinderBot

	# bot自身のscreen_name
	SCREEN_NAME="kiseifinder"

	# NOTIFY_THRESHOLDpostされた時に規制通知
	NOTIFY_THRESHOLD=120

	TIMEF="%Y/%m/%d %H:%M:%S"
	CMD_ITSU=%r[^@#{SCREEN_NAME} +(?:(@?\w+) *)?いつ]
	CMD_RESET=%r[^@#{SCREEN_NAME} +(?:(@?\w+) *)?リセット]

	def initialize
		@config = YAML.load(File.read("config.yaml"))
		@logger = Logger.new($stdout)
	end

	def self.start; self.new.start; end
	def start
		_postprocess = Proc.new do |kf, twitter, tweet, account|
			@logger.info("@#{account.screen_name} #{tweet.id}: post:#{account.post_count} secend:#{account.section_end.strftime(TIMEF)} (#{pretty_time(account.remain_section)})")
			postprocess(kf, twitter, tweet, account)
		end

		_preprocess = Proc.new do |tweet|
			@logger.info("preprocess: @#{tweet.user.screen_name} #{tweet.id}")
			preprocess(tweet)
		end

		KiseiFinder.start(
			:consumer_key    => @config["twitter"]["consumer_key"],
			:consumer_secret => @config["twitter"]["consumer_secret"],
			:access_token    => @config["twitter"]["access_token"],
			:access_secret   => @config["twitter"]["access_secret"],
			:preprocess  => _preprocess,
			:postprocess => _postprocess
		)
	end

	def pretty_time(seconds)
		seconds = seconds.round
		ret  = ""
		ret += "#{seconds/3600}時間" if seconds/3600 > 0
		seconds = seconds%3600
		ret += "#{seconds/60}分" if seconds/60 > 0
		seconds = seconds%60
		ret += "#{seconds}秒" if seconds > 0
		ret
	end

	def postprocess(kf, twitter, tweet, account)
		if account.post_count == NOTIFY_THRESHOLD
			text  = "@#{account.screen_name} "
			text += "規制間近やで"
			text += "(現在#{account.post_count}tweets/section) "
			text += "解除時刻:#{account.section_end.strftime("%H:%M:%S")}"
			text += "(残り:#{pretty_time(account.remain_section)})"
			twitter.update(text, :in_reply_to_status_id => tweet.id)
		end
		case tweet.text
		when CMD_ITSU
			# 対象のscreen_name/Accountオブジェクトを取得
			target_screen_name = tweet.text.match(CMD_ITSU)[1]
			target_screen_name = account.screen_name unless target_screen_name
			target_account = kf.get_account(target_screen_name)

			# 必要であればリセット
			target_account.reset unless target_account.section_start

			# リプライする
			text  = "@#{account.screen_name} "
			text += "現在#{target_account.post_count}tweets/sectionやで "
			text += "解除時刻は#{target_account.section_end.strftime("%H:%M:%S")}"
			text += "(残り:#{pretty_time(target_account.remain_section)})"
			twitter.update(text, :in_reply_to_status_id => tweet.id)
		when CMD_RESET
			# 対象のscreen_name/Accountオブジェクトを取得
			target_screen_name = tweet.text.match(CMD_RESET)[1]
			target_screen_name = account.screen_name unless target_screen_name
			target_account = kf.get_account(target_screen_name)

			# リセット
			target_account.reset

			# リプライする
			text = "@#{account.screen_name} "
			if not target_account.newsection
				text += "#{target_account.screen_name}を" if account != target_account
				text += "リセットしたで！"
				text += "現在#{target_account.post_count}tweets/section "
				text += "解除時刻は#{target_account.section_end.strftime("%H:%M:%S")}"
				text += "(残り:#{pretty_time(target_account.remain_section)})"
			else
				text += "次postが"
				text += "#{target_account.screen_name}の" if account != target_account
				text += "セクション開始やで！"
			end
			twitter.update(text, :in_reply_to_status_id => tweet.id)
		end
	end

	def preprocess(tweet)
		# 受信したpostがbot自身のpost以外の時trueを返して処理を継続
		tweet.user.screen_name != SCREEN_NAME
	end

end

KiseiFinderBot.start

