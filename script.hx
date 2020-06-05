var deliveryTime = [];
var deliveryAmount = [];
var nextDelivery = -1;

var remainingEnemies = [];
var clanHomeZones = [];

var human;
var humanClan;

var notKilled = true;
var notKilled2 = true;

function init() {
	if (state.time == 0)
		onFirstLaunch();

	onEachLaunch();
}

function onFirstLaunch() {

	// Regular food shipments to keep the player alive
	populateDeliveries(calToSeconds(0, 1), 500);
	populateDeliveries(calToSeconds(6, 1), 200);
	populateDeliveries(calToSeconds(1, 2), 700);
	populateDeliveries(calToSeconds(6, 2), 300);
	populateDeliveries(calToSeconds(1, 3), 800);
	populateDeliveries(calToSeconds(2, 4), 600);
	populateDeliveries(calToSeconds(4, 5), 900);

	// All players start with their warchief
	for (player in state.players) {
		var hall:Building = player.getTownHall();

		// The below will create the warchief if none exists. The offset from hall isn't needed
		// as the warchief will spawn inside, and then happily walk outside. However, it looks
		// nicer to offset by a little bit.
		summonWarchief(player, hall.zone, hall.x - 5, hall.y - 5);
	}

	// Give all players food to start
	for (player in state.players) {
		player.addResource(Resource.Food, 500, false);
	}
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
}

function regularUpdate(dt : Float) {
	deliverFoodShipment();

	checkIfPlayerDefeatAI();

	// test to see if defeat code works
	if(state.time > 5 && notKilled) {
		notKilled = false;
		var ai = remainingEnemies[0];
		ai.zones[0].takeControl(human);
	}
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
	if(nextDelivery == -1)
		nextDelivery = deliveryTime.pop();

	if(nextDelivery <= state.time) {
		var amount = deliveryAmount.pop();
		for (player in state.players) {
			player.addResource(Resource.Food, amount, false);
		}
		nextDelivery = deliveryTime.pop();
	}
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
					human.addResource(Resource.Wood, 1000, false);
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