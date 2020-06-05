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

// Human Player Data
var human;
var humanClan;
// END human player data

// Testing stuff
var notKilled = true;
var notKilled2 = true;
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
 * Undocumented feature (found in Discord chat) used to save your properties as needed
 * when the game is saved. Should be restored automatically when game is loaded.
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
		player.addResource(Resource.Wood, 400, false);
		player.addResource(Resource.Money, 600, false);
	}

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

	for (player in state.players) {
		if(player.isAI) {
			remainingEnemies.push(player);
			clanHomeZones.push(player.getTownHall().zone);
		}
		else {
			human = player;
			humanClan = player.clan;
			human.discoverAll();
		}
	}

	state.objectives.add(foodDeliveryObjId, "Next Food Shipment", {showProgressBar:true, autoCheck:false, visible:false});
	state.objectives.setCurrentVal(foodDeliveryObjId, 0);
}

function regularUpdate(dt : Float) {

	checkDifficultySelection();

	deliverFoodShipment();

	updateNextDeliveryProgress();

	checkIfPlayerDefeatAI();

	// test to see if defeat code works
	if(state.time > 3000 && notKilled) {
		notKilled = false;
		var ai = remainingEnemies[0];
		ai.zones[0].takeControl(human);
	}
}

/**
 * Players can choose a difficulty by starting to build a house (easy), scout camp (normal), or logging camp (hard)
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

function setupFoodDelivery() {

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
 * Players get a reward of food for destroying enemy townhalls.
 */
function checkIfPlayerDefeatAI() {
	if(len(state.players) - 1 < remainingEnemies.length) {
		var i = 0;
		while(i < remainingEnemies.length) {
			var p = remainingEnemies[i];
			var found = false;
			for(a in state.players) {
				if(a == p) {
					found = true;
					break;
				}
			}

			if(!found) {

				// Only if the human controls the zone do we give reward
				if(clanHomeZones[i].owner == human)
					human.addResource(Resource.Food, computeFoodReward(), false);
				break;
			}
		}

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

function populateDeliveries(time:Int, amount:Int) {
	deliveryTime.push(time);
	deliveryAmount.push(amount);
}

function calToSeconds(month:Int, year:Int) {

	// 60 seconds per month, and 12 months in a year
	return month * 60 + year * 60 * 12;
}