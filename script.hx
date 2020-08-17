/**
 * ============================================================================
 * 				Mount Doomed
 *
 * This was written when the mod maker was in Beta. If you are still using this
 * when the full version comes out, I wouldn't use this as a reference until
 * I update it to use more of the available features. Many things in here
 * aren't great, but were the only way to do it in Beta.
 *
 * Things that don't work or exist or only we can't do: classes, typedefs,
 * maps, .length on some arrays from the ScriptAPI. Some functions don't
 * work as documented or work weirdly.
 *
 * https://steamcommunity.com/sharedfiles/filedetails/?id=2169950278
 *
 * =============================================================================
 */

// Food delivery data
var deliveryTime:Array<Int> = []; // SAVED
var deliveryAmount:Array<Int> = []; // SAVED

// game time until the next delivery will be made, in seconds.
var nextDelivery = -1; // SAVED
var foodDeliveryObjId = "FOODDELITIME";

// False until the player has made a difficulty selection and the delivery times/amounts are set.
var deliverySetupFinished = false; // SAVED

// This will be false after the final food delivery happens, otherwise it is true
var canDeliverFood = true; // SAVED
// END Food delivery data

// Difficulty selection
var difficulty = null; // SAVED
var diffEasy = "EASY";
var diffNorm = "NORMAL";
var diffHard = "HARD";

var difficultyEasyObjId = "DIFFEASYOBJ";
var difficultyNormObjId = "DIFFNORMOBJ";
var difficultyHardObjId = "DIFFHARDOBJ";
// END difficulty selection

// AI Data

// A list of all the AI players left in the game
var remainingEnemies = [];

// The zones the AI players occupy
var clanHomeZones = [];

var lastMonthFed = 0;
// END AI Data

// Farm zone info
var uncapturedFarmZones = [];
uncapturedFarmZones.push(132);
uncapturedFarmZones.push(107);
uncapturedFarmZones.push(134);
var capFarmsObjId = "FARMCAP";
var allFarmsTaken = false;

var ghostFarmCap = "GHOSTFARMCAP";
var ghostFarmStart:Float = -100;
// END farm zone info

// Human Player Data
var human:Player;
var humanClan;
var warchiefFirstDeath:Bool;
// END human player data

// Dialog Data
var arriveAtIslandText = ["This island has seen many fall before it, looking to plunder its fertile lands.",
							"NO MORE! The fallen now guard these lands.",
							"War amongst yourselves if you must, but if you take our farms, the failures of the past shall haunt you!"
];
var arrivalTextShown = false;

var farmTakenText = "You were warned about taking our farms, now feel our wrath!";
var farmTakenTextShown = false;

var allFarmsTakenText = "Your greed has shown no boundary. We shall show to restraint in taking what is ours!";
var allFarmsTakenTextShown = false;
// END Dialog Data

// Testing stuff
// END testing stuff

/**
 * Called right after the game starts, including after a load (so not just once when the
 * game first starts).
 *
 * @Override
 */
function init() {
	if (state.time == 0)
		onFirstLaunch();

	onEachLaunch();
}

/**
 * Undocumented feature (found in Northgard Discord chat) used to save your properties as needed
 * when the game is saved. Should be restored automatically when game is loaded.
 *
 * NOTE: Saving/Loading does not appear to work at all, so this is just preparation for
 * when that stuff does work. This is a known bug with most all custom maps that add
 * their own objectives to the map. Not much can be done until that is fixed.
 *
 * @Override
 */
function saveState() {
	state.scriptProps = {deliveryTime:deliveryTime, deliveryAmount:deliveryAmount,
			nextDelivery:nextDelivery, difficulty:difficulty, deliverySetupFinished:deliverySetupFinished, canDeliverFood:canDeliverFood};
}

function onFirstLaunch() {

	// All players start with their warchief
	for (player in state.players) {
		var hall:Building = player.getTownHall();

		// The below will create the warchief if none exists. The offset from hall isn't needed
		// as the warchief will spawn inside, and then happily walk outside. However, it looks
		// nicer to offset by a little bit.
		summonWarchief(player, hall.zone, hall.x - 5, hall.y - 5);

		// Give all players resources to start
		player.addResource(Resource.Food, 50, false);
		player.addResource(Resource.Wood, 500, false);
		player.addResource(Resource.Money, 400, false);

		player.addBonus({id:Bonus.BSiloImproved, buildingId:Building.FoodSilo, isAdvanced:false});

		// Reveal the farms at start
		for(i in uncapturedFarmZones)
			player.discoverZone(getZone(i));

		// No need to check if the player is an AI, it just won't work if they're human
		// Not sure what inputs to provide, but the map editor allows -2 to 5 in half increments
		// Going with 5 until devs answer what the values mean.
		player.setAILevel(5);

		// TODO: no way to get the Volcano's zone ID, so we unfortunately can't reveal it
	}

	// Difficulty options
	state.objectives.add(difficultyEasyObjId, "Easy, More Food", {visible:true}, {name:"Easy", action:"callbackEasyDiff"});
	state.objectives.add(difficultyNormObjId, "Normal", {visible:true}, {name:"Medium", action:"callbackMediumDiff"});
	state.objectives.add(difficultyHardObjId, "Hard, Less Food", {visible:true}, {name:"Hard", action:"callbackHardDiff"});

	// All objectives must be setup within the init function, however until a difficulty is chosen we don't want to
	// show this objective.
	state.objectives.add(foodDeliveryObjId, "Next Food Shipment", {showProgressBar:true, autoCheck:false, visible:false});
	state.objectives.setCurrentVal(foodDeliveryObjId, 0);
	state.objectives.add(capFarmsObjId, "Capture the farms", {showProgressBar:true, visible:true});
	state.objectives.setGoalVal(capFarmsObjId, uncapturedFarmZones.length);

	state.objectives.add(ghostFarmCap, "The spirits lost their farm!", {visible:false});
}

function onEachLaunch() {

	// Setup Dom only victory
	state.removeVictory(VictoryKind.VMoney);
	state.removeVictory(VictoryKind.VFame);
	state.removeVictory(VictoryKind.VLore);

	// Setup map rules
	addRule(Rule.VillagerStrike);
	addRule(Rule.SuperScout);
	addRule(Rule.Eruptions); // Only works year > 2 years, see DB->Events
	addRule(Rule.LethalRuins);

	// grab all the players, and for the AI store their homes
	// so we can figure out when they were defeated and who defeated them.
	for (player in state.players) {
		if(player.isAI) {
			remainingEnemies.push(player);
			clanHomeZones.push(player.getTownHall().zone);
		}
	}

	// In a singleplayer game, me() returns the human player.
	human = me();
	humanClan = human.clan;
}

/**
 * This is called every 0.5 seconds. There is a maximum runtime allowed (I think 500ms) or else the entire game
 * crashes. This is undocumented, but was found in the Northgard Discord chat.
 *
 * @Override
 */
function regularUpdate(dt : Float) {

	// The editor will complain about @split, but it seems to work anyway.
	@split[
	timedDialog(),

	checkDifficultySelection(),

	deliverFoodShipment(),

	// giveAIBonus(),

	updateNextDeliveryProgress(),

	checkIfPlayerDefeatAI(),

	checkForCapturedFarms(),

	fadeOutMessages(),
	];
}

/**
 * The AI don't know how to play the map and will starve themselves to death.
 * Unfortunately, the regular pushes of food to the AI aren't enough. Instead,
 * we give the AI food equal to its pop every month to keep it alive.
 */
function giveAIBonus() {

	// We only want to trigger this bonus once a month
	var currentMonth = convertTimeToMonth(state.time);
	if(lastMonthFed == currentMonth)
		return;

	lastMonthFed = currentMonth;

	for(p in remainingEnemies) {
		var villagerCount = 0;
		for(u in p.units)
			if(u.kind == Unit.Villager)
				villagerCount++;
		p.addResource(Resource.Food, villagerCount * 6 * 2);
	}
}

function timedDialog() {
	if(state.time > 5 && !arrivalTextShown) {
		setPause(true);
		for(text in arriveAtIslandText)
			talk(text, {name:"Hungry Spirits", who:Banner.Giant1});
		arrivalTextShown = true;
		setPause(false);

	}
}

/**
 * We can't directly send messages to the player, so using objectives
 * isn't a bad system. Throw in any messages you want to get rid of after
 * some time.
 */
function fadeOutMessages() {
	if(ghostFarmStart + 30 < state.time) {
		state.objectives.setVisible(ghostFarmCap, false);
		ghostFarmStart = -100;
	}
}

/**
 * If any players capture a farm for the first time, then Fallen Sailors event is launched.
 */
function checkForCapturedFarms() {

	// No point in doing the below if all farms are taken.
	if(allFarmsTaken)
		return;

	var capturedFarm = -1;

	for(z in uncapturedFarmZones) {
		var zone = getZone(z);
		var owner = zone.owner;

		// Find the player that took it, if any
		for(p in state.players) {
			if(owner == p) {
				capturedFarm = z;
				state.events.setEvent(Event.FallenSailors, 1);
				state.objectives.setVisible(ghostFarmCap, true);
				ghostFarmStart = state.time;
			}
		}
	}

	// If it was taken, then let's not consider it in the future and update the objective.
	if(capturedFarm != -1) {
		if(!farmTakenTextShown) {
			pauseAndShowDialog(farmTakenText, "Hungry Spirits", Banner.Giant1);
			farmTakenTextShown = true;
		}
		uncapturedFarmZones.remove(capturedFarm);
		state.objectives.setCurrentVal(capFarmsObjId, 3 - uncapturedFarmZones.length);
	}

	if(uncapturedFarmZones.length == 0 && !allFarmsTakenTextShown) {
		pauseAndShowDialog(allFarmsTakenText, "Vengeful Spirits", Banner.Giant1);
		allFarmsTakenTextShown = true;
		allFarmsTaken = true;
	}
}

/**
 * A helper function to reduce clutter in other functions by pausing to show a single line of text.
 */
function pauseAndShowDialog(text, name, who) {
	setPause(true);
	talk(text, {name:name, who:who});
	setPause(false);
}

/**
 * The difficulty Objectives need to disappear after some time.
 */
function checkDifficultySelection() {
	if(difficulty != null && state.time > 90) {
		state.objectives.setVisible(difficultyEasyObjId, false);
		state.objectives.setVisible(difficultyNormObjId, false);
		state.objectives.setVisible(difficultyHardObjId, false);
	}
}

/**
 * Updates the progress bar under the objective, indicating how many days until next food shipment.
 */
function updateNextDeliveryProgress() {
	state.objectives.setCurrentVal(foodDeliveryObjId, state.time);
}

/**
 * Doesn't seem like the .remove() function works for Player objects.
 * Use this function to refresh the list of remaining AI
 */
function getRemainingEnemies() {
	remainingEnemies = [];
	clanHomeZones = [];
	for (p in state.players) {
		if(p.isAI) {
			remainingEnemies.push(p);
			clanHomeZones.push(p.getTownHall().zone);
		}
	}
}

/**
 * This will determine what food shipment to give the player and when.
 * Once a food shipment is made, the next one is automatically pulled.
 *
 * No food shipment will be made until a difficulty is chosen, which will then
 * populate all the food delivery data.
 */
function deliverFoodShipment() {

	if(difficulty != null && !deliverySetupFinished) {
		setupFoodDelivery();
	}
	else if(deliverySetupFinished) {
		if(canDeliverFood) {
			if(nextDelivery == -1) {
				nextDelivery = deliveryTime.shift();
				state.objectives.setGoalVal(foodDeliveryObjId, nextDelivery);
				state.objectives.setVisible(foodDeliveryObjId, true);
			}

			if(nextDelivery <= state.time) {
				var amount = deliveryAmount.shift();
				for (p in state.players) {
					p.addResource(Resource.Food, amount, false);
				}
				if(deliveryTime.length == 0) {
					canDeliverFood = false;
				}
				else {
					nextDelivery = deliveryTime.shift();
					state.objectives.setGoalVal(foodDeliveryObjId, nextDelivery);
				}
			}
		}
	}
}

/**
 * Just setups the food delivery data based on difficulty. Only call this once.
 */
function setupFoodDelivery() {

	// Just a guard to make sure we don't call this twice.
	if(deliverySetupFinished)
		return;

	// Regular food shipments to keep the player alive
	switch(difficulty) {
		case diffEasy:
			populateDeliveries(calToSeconds(1, 0), 500);
			populateDeliveries(calToSeconds(9, 0), 500);
			populateDeliveries(calToSeconds(11, 0), 200);
			populateDeliveries(calToSeconds(0, 1), 400);
			populateDeliveries(calToSeconds(4, 1), 200);
			populateDeliveries(calToSeconds(7, 1), 700);
			populateDeliveries(calToSeconds(10, 1), 200);
			populateDeliveries(calToSeconds(1, 2), 700);
			populateDeliveries(calToSeconds(5, 2), 150);
			populateDeliveries(calToSeconds(8, 2), 1100);
			populateDeliveries(calToSeconds(2, 3), 600);
			populateDeliveries(calToSeconds(9, 3), 900);
			populateDeliveries(calToSeconds(4, 4), 700);
			populateDeliveries(calToSeconds(10, 4), 200);
			populateDeliveries(calToSeconds(3, 5), 500);
			populateDeliveries(calToSeconds(9, 5), 500);
			populateDeliveries(calToSeconds(2, 6), 1000);
		case diffNorm:
			populateDeliveries(calToSeconds(1, 0), 500);
			populateDeliveries(calToSeconds(9, 0), 300);
			populateDeliveries(calToSeconds(0, 1), 200);
			populateDeliveries(calToSeconds(7, 1), 500);
			populateDeliveries(calToSeconds(1, 2), 300);
			populateDeliveries(calToSeconds(8, 2), 400);
			populateDeliveries(calToSeconds(2, 3), 400);
			populateDeliveries(calToSeconds(11, 3), 400);
			populateDeliveries(calToSeconds(9, 4), 400);
			populateDeliveries(calToSeconds(3, 5), 400);
		case diffHard: // The same as normal for now
			populateDeliveries(calToSeconds(1, 0), 500);
			populateDeliveries(calToSeconds(9, 0), 300);
			populateDeliveries(calToSeconds(0, 1), 200);
			populateDeliveries(calToSeconds(7, 1), 500);
			populateDeliveries(calToSeconds(1, 2), 300);
			populateDeliveries(calToSeconds(8, 2), 400);
			populateDeliveries(calToSeconds(2, 3), 400);
			populateDeliveries(calToSeconds(11, 3), 400);
			populateDeliveries(calToSeconds(9, 4), 400);
			populateDeliveries(calToSeconds(3, 5), 400);
	}

	deliverySetupFinished = true;
}

/**
 * Players get a reward of food for destroying enemy townhalls, but only if the human
 * is the player to take the territory when the AI was defeated. If the AI takes it, no
 * reward is given.
 */
function checkIfPlayerDefeatAI() {
	if(len(state.players) - 1 < remainingEnemies.length) {
		var i = 0;

		// try to figure out which AI is missing
		// NOTE: be very careful with loops which aren't for-each
		// If you forget to increment the value, you'll infinite loop and
		// cause a CTD
		while(i < remainingEnemies.length) {
			var p = remainingEnemies[i];
			var found = false;
			for(a in state.players) {
				if(a == p) {
					found = true;
					break;
				}
			}

			// If we can't find the AI in the list of remaining players, that means
			// we found the defeated AI
			if(!found) {

				// Only if the human has a unit in the territory that is theirs
				// do they get the reward. Note: we sample the first unit and assume that is enough
				if(clanHomeZones[i].units[0].isOwner(human))
					human.addResource(Resource.Food, computeFoodReward(), false);
				break;
			}
			i++;
		}

		// Keep this list updated
		getRemainingEnemies();
	}
}

/**
 * Some arrays from ScriptAPI seem to have busted length field members. This function
 * computes the length for those arrays.
 *
 * Example, state.players
 */
function len(a):Int {
	var len = 0; for(p in a) len++; return len;
}

/**
 * Some arrays from ScriptAPI seem to have busted length field members. This function
 * computes the length for those arrays.
 *
 * Example, state.players
 */
function lenU(a:Array<Unit>):Int {
	var len = 0; for(p in a) len++; return len;
}

/**
 * Players get a decreasing amount of food based on the current time.
 * After year 10, no food is given.
 *
 * Food reward is a hyperbolic function
 */
function computeFoodReward() {
	return state.time > calToSeconds(0, 10) ? 0 : 1.6 / (5 + 0.005 * state.time) * 10000;
}

/**
 * Just a helper function to make sure the correct data structures are used when
 * adding a new delivery.
 */
function populateDeliveries(time:Int, amount:Int) {
	deliveryTime.push(time);
	deliveryAmount.push(amount);
}

/**
 * Given a Month and Year, it will return the number of real time seconds that
 * represents. A Month is defined as 60 seconds long. One year is therefore
 * 720 seconds or 12 minutes.
 */
function calToSeconds(month:Int, year:Int) {

	// 60 seconds per month, and 12 months in a year
	return month * 60 + year * 60 * 12;
}

/**
 * Given a time, will return what month we are in, where 0 = March and 12 = February
 */
function convertTimeToMonth(time:Float) {
	return toInt(time % 720 / 60);
}

function callbackEasyDiff() {
	difficulty = diffEasy;
	state.objectives.setStatus(difficultyEasyObjId, OStatus.Done);
	state.objectives.setStatus(difficultyNormObjId, OStatus.Missed);
	state.objectives.setStatus(difficultyHardObjId, OStatus.Missed);
}

function callbackMediumDiff() {
	difficulty = diffNorm;
	state.objectives.setStatus(difficultyEasyObjId, OStatus.Missed);
	state.objectives.setStatus(difficultyNormObjId, OStatus.Done);
	state.objectives.setStatus(difficultyHardObjId, OStatus.Missed);
}

function callbackHardDiff() {
	difficulty = diffHard;
	state.objectives.setStatus(difficultyEasyObjId, OStatus.Missed);
	state.objectives.setStatus(difficultyNormObjId, OStatus.Missed);
	state.objectives.setStatus(difficultyHardObjId, OStatus.Done);
	debug("Hard difficulty is the same as normal difficulty, I haven't worked it out yet, sorry :(");
}