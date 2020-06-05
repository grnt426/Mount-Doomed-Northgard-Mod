/**
 * =======================================
 * 				Mount Doomed
 *
 * This was written when the mod maker was in Beta. If you are still using this
 * when the full version comes out, I wouldn't use this as a reference until
 * I update it to use more of the available features. Many things in here
 * aren't great, but were the only way to do it in Beta.
 *
 * Things that don't work/exist or only we can't do: classes, typedefs,
 * maps, .length on some arrays from the ScriptAPI. Some functions don't
 * work as documented or work weirdly.
 *
 * =======================================
 */

// Food delivery data
var deliveryTime = []; // SAVED
var deliveryAmount = []; // SAVED
var nextDelivery = -1; // SAVED
var foodDeliveryObjId = "FOODDELITIME";
var deliverySetupFinished = false; // SAVED
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

// AI town zone info
var remainingEnemies = [];
var clanHomeZones = [];
// END AI town zone info

// Farm zone info
var uncapturedFarmZones = [];
uncapturedFarmZones.push(132);
uncapturedFarmZones.push(107);
uncapturedFarmZones.push(134);
var capFarmsObjId = "FARMCAP";

var ghostFarmCap = "GHOSTFARMCAP";
var ghostFarmStart:Float = -100;
// END farm zone info

// Human Player Data
var human;
var humanClan;
// END human player data

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
			nextDelivery:nextDelivery, difficulty:difficulty, deliverySetupFinished:deliverySetupFinished};
}

function onFirstLaunch() {

	// All players start with their warchief
	for (player in state.players) {
		var hall:Building = player.getTownHall();

		// The below will create the warchief if none exists. The offset from hall isn't needed
		// as the warchief will spawn inside, and then happily walk outside. However, it looks
		// nicer to offset by a little bit.
		summonWarchief(player, hall.zone, hall.x - 5, hall.y - 5);
	}

	// Give all players resources to start
	for (player in state.players) {
		player.addResource(Resource.Food, 50, false);
		player.addResource(Resource.Wood, 500, false);
		player.addResource(Resource.Money, 400, false);
	}

	// To remind players how to choose the difficulty.
	state.objectives.add(difficultyEasyObjId, "Build House for Easy");
	state.objectives.add(difficultyNormObjId, "Build Scout Camp for Normal");
	state.objectives.add(difficultyHardObjId, "Build Logging Camp for Hard");
}

function onEachLaunch() {

	// Setup Dom only victory
	state.removeVictory(VictoryKind.VMoney);
	state.removeVictory(VictoryKind.VFame);
	state.removeVictory(VictoryKind.VLore);

	// Setup map rules
	addRule(Rule.VillagerStrike);
	addRule(Rule.SuperScout);
	addRule(Rule.Eruptions);
	addRule(Rule.LethalRuins);

	// grab all the players, figure out which one is Human, and for the AI store their homes
	// so we can figure out when they were defeated and who defeated them.
	for (player in state.players) {
		if(player.isAI) {
			remainingEnemies.push(player);
			clanHomeZones.push(player.getTownHall().zone);
		}
		else {
			human = player;
			humanClan = player.clan;

			// The DB was modified to allow players to build them wherever they have ports, their town hall, or farms.
			// They also store more food total, and increase production much further
			// NOTE: the actual bonus doesn work, so it is commented out for now so as to not confuse the player
			// human.addBonus({id:Bonus.BSilo, buildingId:Building.FoodSilo, isAdvanced:false});
		}
	}

	// All objectives must be setup within the init function, however until a difficulty is chosen we don't want to
	// show this objective.
	state.objectives.add(foodDeliveryObjId, "Next Food Shipment", {showProgressBar:true, autoCheck:false, visible:false});
	state.objectives.setCurrentVal(foodDeliveryObjId, 0);
	state.objectives.add(capFarmsObjId, "Capture the farms", {showProgressBar:true, visible:true});
	state.objectives.setGoalVal(capFarmsObjId, uncapturedFarmZones.length);

	state.objectives.add(ghostFarmCap, "The spirits lost their farm!", {visible:false});
}

/**
 * This is called 0.5 seconds. There is a maximum runtime allowed (I think 500ms) or else the entire game
 * crashes. This is undocumented, but was found in the Northgard Discord chat.
 *
 * @Override
 */
function regularUpdate(dt : Float) {



	checkDifficultySelection();

	deliverFoodShipment();

	updateNextDeliveryProgress();

	checkIfPlayerDefeatAI();

	checkForCapturedFarms();

	fadeOutMessages();
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
	var capturedFarm = -1;

	for(z in uncapturedFarmZones) {
		var zone = getZone(z);
		var owner = zone.owner;

		// Find the player that took it, if any
		for(p in state.players) {
			if(owner == p) {
				capturedFarm = z;
				launchEvent(Event.FallenSailors, 1, 3);
				state.objectives.setVisible(ghostFarmCap, true);
				ghostFarmStart = state.time;
			}
		}
	}

	// If it was taken, then let's not consider it in the future and update the objective.
	if(capturedFarm != -1) {
		uncapturedFarmZones.remove(capturedFarm);
		state.objectives.setCurrentVal(capFarmsObjId, 3 - uncapturedFarmZones.length);
	}
}

/**
 * Players can choose a difficulty by starting to build a house (easy), scout camp (normal), or logging camp (hard).
 * Once a difficulty has been chosen, it can't be changed. The difficulty Objectives will disappear after some time.
 */
function checkDifficultySelection() {
	if(difficulty == null) {
		if(human.hasBuilding(Building.House, true)) {
			difficulty = diffEasy;
			state.objectives.setStatus(difficultyEasyObjId, OStatus.Done);
			state.objectives.setStatus(difficultyNormObjId, OStatus.Missed);
			state.objectives.setStatus(difficultyHardObjId, OStatus.Missed);
		}
		else if(human.hasBuilding(Building.ScoutCamp, true)) {
			difficulty = diffNorm;
			state.objectives.setStatus(difficultyEasyObjId, OStatus.Missed);
			state.objectives.setStatus(difficultyNormObjId, OStatus.Done);
			state.objectives.setStatus(difficultyHardObjId, OStatus.Missed);
		}
		else if(human.hasBuilding(Building.WoodLodge, true)) {
			difficulty = diffHard;
			state.objectives.setStatus(difficultyEasyObjId, OStatus.Missed);
			state.objectives.setStatus(difficultyNormObjId, OStatus.Missed);
			state.objectives.setStatus(difficultyHardObjId, OStatus.Done);
		}
	}
	else {
		if(state.time > 90) {
			state.objectives.setVisible(difficultyEasyObjId, false);
			state.objectives.setVisible(difficultyNormObjId, false);
			state.objectives.setVisible(difficultyHardObjId, false);
		}
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
	for (player in state.players) {
		if(player.isAI) {
			remainingEnemies.push(player);
			clanHomeZones.push(player.getTownHall().zone);
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
		if(nextDelivery == -1) {
			nextDelivery = deliveryTime.shift();
			state.objectives.setGoalVal(foodDeliveryObjId, nextDelivery);
			state.objectives.setVisible(foodDeliveryObjId, true);
		}

		if(nextDelivery <= state.time) {
			var amount = deliveryAmount.shift();
			for (player in state.players) {
				player.addResource(Resource.Food, amount, false);
			}
			nextDelivery = deliveryTime.shift();
			state.objectives.setGoalVal(foodDeliveryObjId, nextDelivery);
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
			populateDeliveries(calToSeconds(0, 1), 200);
			populateDeliveries(calToSeconds(7, 1), 700);
			populateDeliveries(calToSeconds(1, 2), 300);
			populateDeliveries(calToSeconds(8, 2), 800);
			populateDeliveries(calToSeconds(2, 3), 600);
			populateDeliveries(calToSeconds(11, 3), 900);
			populateDeliveries(calToSeconds(5, 4), 700);
			populateDeliveries(calToSeconds(11, 4), 200);
			populateDeliveries(calToSeconds(5, 5), 500);
			populateDeliveries(calToSeconds(11, 5), 500);
			populateDeliveries(calToSeconds(5, 6), 1000);
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

				// Only if the human controls the zone do we give reward
				if(clanHomeZones[i].owner == human)
					human.addResource(Resource.Food, computeFoodReward(), false);
				break;
			}
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
 * Players get a decreasing amount of food based on the current time.
 * After year 10, no food is given.
 */
function computeFoodReward() {
	return state.time > calToSeconds(0, 10) ? 0 : 2000 * (1 - state.time / calToSeconds(0, 10));
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
 *
 *
 */
function calToSeconds(month:Int, year:Int) {

	// 60 seconds per month, and 12 months in a year
	return month * 60 + year * 60 * 12;
}