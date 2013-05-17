#!/usr/bin/ruby
# -*- coding: utf-8 -*-

$stdout.sync = true
$stderr.sync = true

require 'pp'
require 'yaml'
require './kiseifinder'

# bot自身のscreen_name
SCREEN_NAME="kiseifinder"

# NOTIFY_THRESHOLDpostされた時に規制通知
NOTIFY_THRESHOLD=120

TIMEF="%Y/%m/%d %H:%M:%S"
CMD_ITSU=%r[^@#{SCREEN_NAME} +(?:(@?\w+) *)?いつ]
CMD_RESET=%r[^@#{SCREEN_NAME} +(?:(@?\w+) *)?リセット]

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

postprocess = Proc.new do |kf, twitter, tweet, account|
	puts "@#{account.screen_name} pc:#{account.post_count} rt:\"#{account.section_end.strftime(TIMEF)}\" (#{pretty_time(account.remain_section)})"
	if account.post_count == NOTIFY_THRESHOLD
		twitter.update("@#{account.screen_name} 規制間近やで(現在#{account.post_count}tweets/section) 解除時刻:#{account.section_end.strftime("%H:%M:%S")}(残り:#{pretty_time(account.remain_section)})")
	end
	case tweet.text
	when CMD_ITSU
		target_screen_name = tweet.text.match(CMD_ITSU)[1]
		target_screen_name = account.screen_name unless target_screen_name
		target_account = kf.get_account(target_screen_name)
		target_account.reset unless target_account.section_start
		twitter.update("@#{account.screen_name} 現在#{target_account.post_count}tweets/sectionやで 解除時刻は#{target_account.section_end.strftime("%H:%M:%S")}(残り:#{pretty_time(target_account.remain_section)})やで", :in_reply_to_status_id => tweet.id)
	when CMD_RESET
		target_screen_name = tweet.text.match(CMD_RESET)[1]
		target_screen_name = account.screen_name unless target_screen_name
		target_account = kf.get_account(target_screen_name)
		target_account.reset

		text  = "@#{account.screen_name} "
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

preprocess = Proc.new do |tweet|
	# 受信したpostのユーザのscreen_nameがbot自身のscreen_nameであれば処理しない
	next false if tweet.user.screen_name == SCREEN_NAME
	next true
end

config = YAML.load(File.read("config.yaml"))

KiseiFinder.start(
	:consumer_key => config["twitter"]["consumer_key"],
	:consumer_secret => config["twitter"]["consumer_secret"],
	:access_token => config["twitter"]["access_token"],
	:access_secret => config["twitter"]["access_secret"],
	:preprocess => preprocess,
	:postprocess => postprocess
)
