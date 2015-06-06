
console.log "Starting Reddit Hounds CoC Analyzer..."

require "sugar"
ss = require 'simple-statistics'
ss.mixin()

prompt = require("prompt")
async = require 'async'
playerMap = require "#{__dirname}/player-map"
	
fs = require 'fs'

targetStarMultiplier = 2.3
baseDeductionValue = 0.25
baseBonusValue = 0.5
missedAttackValue = 0.75
warLossMultiplier = 1.5
topPercentageBonusValue = 0.5
topAttackModifier = 1.5
targetPlayerName = ""

if "--target-player" in process.argv and targetPlayerName.length is 0
	targetPlayerName = process.argv[process.argv.indexOf("--target-player") + 1]

if targetPlayerName?.length > 0
	console.log "Analyzing",targetPlayerName

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
	
analyzeWars = (wars,cb0) ->
	userMap = {}
	warNames = []
	
	for war in wars
	
		if targetPlayerName?.length > 0
			console.log war.opponent
		
		warNames.push war.opponent
		war.targetStars = targetStarMultiplier * war.size
		painLevel = if war.outcome then 1 else warLossMultiplier
		
		for player in war.players
			if playerMap.renamed[player.name]?
				player.name = playerMap.renamed[player.name]
			if not (player.name in playerMap.kicked)
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
					userMap[player.name].totalScore -= diff*missedAttackValue*painLevel
				if player.name is targetPlayerName
					console.log "\tRank: #{player.rank}"
				for attack in player.attacks
					if player.name is targetPlayerName
						console.log "\tAttacked #{attack.opponentRank}"
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
					else if player.percentile > 0.8
						# BOTTOM END
						attack.illegal = attack.illegal || attack.opponentRank < player.rank - war.size*0.3
					else
						# ERRBODY IN BETWEEN
						attack.illegal = attack.opponentRank <= player.rank and 0.8 > player.percentile > 0.2
					
					if attack.illegal
						userMap[player.name].illegalAttacks++
				
				if player.name is targetPlayerName
					console.log "\tBase: ",player.attacks.map((a) -> if a.totalStars is 3 then a.totalStars else a.newStars).sum(),'-',player.starsAgainst,'=',player.attacks.map((a) -> if ((a.totalStars is 3) and (a.newStars > 0)) then a.totalStars else a.newStars).sum() - (player.starsAgainst)
				userMap[player.name].totalScore += player.attacks.map((a) -> if ((a.totalStars is 3) and (a.newStars > 0)) then a.totalStars else a.newStars).sum()*(if player.percentile < 0.2 and attack.opponentRank - player.rank <= player.rank then topAttackModifier else 1) - (player.starsAgainst)
				
				if player.rank <= 0.1*war.size 
					if player.starsAgainst is 0
						if player.name is targetPlayerName
							console.log "\tBase bonus"
						userMap[player.name].totalScore += baseBonusValue
						userMap[player.name].baseBonuses++
				else if 0.1*war.size < player.rank <= 0.4*war.size 
					if player.starsAgainst > 2
						if player.name is targetPlayerName
							console.log "\tBase deduction"
						userMap[player.name].totalScore -= baseDeductionValue
						userMap[player.name].baseDeductions++
					else if player.starsAgainst < 2
						if player.name is targetPlayerName
							console.log "\tBase bonus"
						userMap[player.name].totalScore += baseBonusValue
						userMap[player.name].baseBonuses++
				else
					if player.starsAgainst < 3
						if player.name is targetPlayerName
							console.log "\tBase bonus"
						userMap[player.name].totalScore += baseBonusValue
						userMap[player.name].baseBonuses++				
	
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
		user.score = parseFloat (user.totalScore/user.warCount).toFixed(2)
		
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
	
	currentRank = 0
	lastScore = 1000000000000000000000000
	totalUsers = 0
	for user in users
		totalUsers++
		if user.score < lastScore
			lastScore = user.score
			currentRank = totalUsers
		if not (targetPlayerName?.length > 0) or user.name is targetPlayerName
			console.log "#{currentRank}:",user.name
			if user.name is targetPlayerName
				console.log "\tRaw: #{user.totalScore}"
			console.log "\tAverage Rank Diff: #{if user.averageRankDifference >= 0 then '+' else ''}#{user.averageRankDifference.toFixed(2)}"
			console.log "\tBase Bonuses - Deductions: #{user.baseBonuses} - #{user.baseDeductions} = #{user.baseBonuses - user.baseDeductions}"
			console.log "\tWar Participation: #{user.warCount}/#{wars.length}"
			console.log "\tScore: #{if user.score >= 0 then '+' else ''}#{user.score}"
		
	console.log "Using Wars:",warNames
	
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
		
	cb0 null
		
if "--new-war" in process.argv

	prompt.message = ""
	prompt.delimeter = ""
	prompt.colors = false
	
	prompt.start()
	
	data = {}
	
	prompt.get ['opponent','size','outcome'], (err,result) ->
		handleError err
		dataFxns = []
		data.opponent = result.opponent
		data.size = parseInt(result.size)
		data.outcome = result.outcome.toLowerCase() in ['win','w','1','true','t','victory','v']
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
				
else if "--analyze" in process.argv
	paths = process.argv.slice 3,process.argv.length
	readFiles paths, (err,wars) ->
		handleError err
		analyzeWars wars, ->
			process.exit 0
		
		
else if "--analyze-all" in process.argv

	fs.readdir ".",(err,paths) ->
		
		paths = paths.filter (f) ->
			f.endsWith(".json") and not (f in ["package.json","bower.json"])
			
		readFiles paths, (err,wars) ->
			handleError err
			analyzeWars wars, ->
				process.exit 0
				
else if "--analyze-recent" in process.argv

	fs.readdir ".",(err,paths) ->
		
		paths = paths.filter (f) ->
			f.endsWith(".json") and not (f in ["package.json","bower.json"])
			
		readFiles paths, (err,wars) ->
			handleError err
			bound = (new Date()).getTime() - 1000*60*60*24*7*parseInt(process.argv[3])
			wars = wars.filter (w) -> (new Date(w.date)).getTime() > bound
			analyzeWars wars, ->
				process.exit 0

else
	console.log "Invalid start up options."