
console.log "Starting Reddit Hounds CoC Analyzer..."

require "sugar"
ss = require 'simple-statistics'
ss.mixin()

prompt = require("prompt")
async = require 'async'
	
fs = require 'fs'

targetStarMultiplier = 2.3
baseDeductionValue = 0.25
baseBonusValue = 0.5
missedAttackValue = 0.75

handleError = (err) ->
	if err?
		console.error err
		process.exit 1
		
readFiles = (fileArray,callback) ->
	readFxns = []
	for i in [0...fileArray.length]
		do (i) ->
			readFxns.push (cb1) ->
				fs.readFile fileArray[i],{encoding:'utf8'}, (err,data) ->
					handleError err
					cb1 null,JSON.parse data
	async.parallel readFxns, callback
		
if process.argv[2] is "--new-war"

	prompt.message = ""
	prompt.delimeter = ""
	prompt.colors = false
	
	prompt.start()
	
	data = {}
	
	prompt.get ['opponent','size'], (err,result) ->
		handleError err
		dataFxns = []
		data.opponent = result.opponent
		data.size = parseInt(result.size)
		for i in [0...data.size]
			do (i) ->
				dataFxns.push (callback) ->
					playerData = {}
					console.log "Chief #{i+1}:"
					prompt.get ['name','attacksUsed','starsAgainst'], (err,results) ->
						results.attacksUsed = parseInt(results.attacksUsed)
						results.starsAgainst = parseInt(results.starsAgainst)
						playerData.name = results.name
						playerData.starsAgainst = results.starsAgainst
						playerData.attacks = []
						playerData.rank = i+1
						attackPrompts = []
						for j in [0...results.attacksUsed]
							do (j) ->
								attackPrompts.push (cb2) ->
									console.log "Attack #{j+1}:"
									prompt.get ['totalStars','newStars','opponentRank'], (err,results) ->
										results.totalStars = parseInt(results.totalStars)
										results.newStars = parseInt(results.newStars)
										results.opponentRank = parseInt(results.opponentRank)
										handleError err
										playerData.attacks.push results
										cb2 err,null
										
						async.series attackPrompts, (err,results) ->
							handleError err
							callback null,playerData
									
		async.series dataFxns, (err,results) ->
			handleError err
			console.log results
			data.players = results
			prompt.get ['destinationFile'], (err,results) ->
				handleError err
				data.date = (new Date()).toISOString()
				fs.writeFileSync results.destinationFile, JSON.stringify(data)
				process.exit 0
				
else if process.argv[2] is "--analyze"
	paths = process.argv.slice 3,process.argv.length
	readFiles paths, (err,wars) ->
		handleError err
		
		userMap = {}
		warNames = []
		
		for war in wars
			
			warNames.push war.opponent
			war.targetStars = targetStarMultiplier * war.size
			
			for player in war.players
			
				player.percentile = player.rank/war.size
				
				if not userMap[player.name]?
					userMap[player.name] = 
						name: player.name
						totalStars: 0
						newStars: 0
						zeroStarAttacks: 0
						threeStarAttacks: 0
						attacksMissed: 0
						warCount: 0
						attackCount: 0
						myRankSum: 0
						opponentRankSum: 0
						illegalAttacks: 0
						totalScore: 0
						baseDeductions: 0
						baseBonuses: 0
						
				userMap[player.name].warCount++
				userMap[player.name].myRankSum += player.rank
				
				if player.attacks.length < 2
					diff = 2 - player.attacks.length
					userMap[player.name].attacksMissed += diff
					userMap[player.name].totalScore -= diff*missedAttackValue
					
					
				for attack in player.attacks
					userMap[player.name].attackCount++
					if attack.totalStars is 0
						userMap[player.name].zeroStarAttacks++
					else if attack.totalStars is 3
						userMap[player.name].threeStarAttacks++
					userMap[player.name].opponentRankSum += attack.opponentRank
					userMap[player.name].totalStars += attack.totalStars
					userMap[player.name].newStars += attack.newStars
					
					attack.illegal = false
					if player.percentile < 0.2
						# TOP END
						attack.illegal = attack.illegal || attack.opponentRank > player.rank + war.size*0.3
						if not attack.illegal and attack.totalStars > 0
							userMap[player.name].totalScore++
					else if player.percentile > 0.8
						# BOTTOM END
						attack.illegal = attack.illegal || attack.opponentRank < player.rank - war.size*0.3
					else
						# ERRBODY IN BETWEEN
						attack.illegal = attack.opponentRank <= player.rank and 0.8 > player.percentile > 0.2
					
					if attack.illegal
						userMap[player.name].illegalAttacks++
						
				userMap[player.name].totalScore += player.attacks.map((a) -> if a.totalStars is 3 then a.totalStars else a.newStars).sum() - (player.starsAgainst || 0)
				
				if player.rank <= 0.1*war.size 
					if player.starsAgainst > 1
						userMap[player.name].totalScore -= baseDeductionValue
						userMap[player.name].baseDeductions++
					else if player.starsAgainst is 0
						userMap[player.name].totalScore += baseBonusValue
						userMap[player.name].baseBonuses++
				else if 0.1*war.size > player.rank >= 0.4*war.size 
					if player.starsAgainst > 2
						userMap[player.name].totalScore -= baseDeductionValue
						userMap[player.name].baseDeductions++
					else if player.starsAgainst < 2
						userMap[player.name].totalScore += baseBonusValue
						userMap[player.name].baseBonuses++
				else
					if player.starsAgainst < 3
						userMap[player.name].totalScore += baseBonusValue
						userMap[player.name].baseBonuses++
					
					
					
			
#			for player in war.players
				
		
		users = []
		for k,v of userMap
			users.push v
			
		averageWarCount = users.map((u) -> u.warCount).mean()
		
		for user in users
			user.averageRank = user.myRankSum/user.warCount
			user.averageOpponentRank = user.opponentRankSum/user.attackCount
			user.averageNewStars = user.newStars/user.attackCount
			user.averageTotalStars = user.totalStars/user.attackCount
			user.averageRankDifference = user.averageRank - user.averageOpponentRank
			user.score = parseFloat (user.totalScore/averageWarCount).toFixed(2)
		
		stats = {}
		stats.medianRankDifference = users.map((u) -> u.averageRankDifference).median()
		stats.mad = ss.mad users.map((u) -> u.averageRankDifference)
		#stats.iqr = ss.interquartile_range(users.map((u) -> u.averageRankDifference))
#		console.dir stats
		
		users.sort (a,b) ->
			if a.score > b.score
				return -1
			else if a.score < b.score
				return 1
			else
				if a.averageRank > b.averageRank
					return -1
				else
					return 1
			
		console.log "Using Wars:",warNames
#		console.dir users
		for user in users
			console.log user.name
			console.log "\tAverage Rank Diff: #{if user.averageRankDifference >= 0 then '+' else ''}#{user.averageRankDifference}"
			console.log "\tBase Bonuses: #{user.baseBonuses}" if user.baseBonuses > 0
			console.log "\tBase Deductions: #{user.baseDeductions}" if user.baseDeductions > 0
			console.log "\tScore: #{if user.score >= 0 then '+' else ''}#{user.score}"
			
		console.log "Out of Bounds Attackers:",users.filter((u) -> u.illegalAttacks > u.warCount/2).sort((a,b) ->
			if a.illegalAttacks > b.illegalAttacks
				return -1
			else if a.illegalAttacks < b.illegalAttacks
				return 1
			else
				if a.averageRank > b.averageRank
					return -1
				else
					return 1
		).map((u) -> "#{u.name}: #{u.illegalAttacks}")
			
		
		stats = {}
		stats.medianRankDifference = users.map((u) -> u.averageRankDifference).median()
		stats.mad = ss.mad users.map((u) -> u.averageRankDifference)
		#stats.iqr = ss.interquartile_range(users.map((u) -> u.averageRankDifference))
#		console.dir stats
		process.exit 0
		
	