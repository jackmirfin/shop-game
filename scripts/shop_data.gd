class_name ShopData
extends Resource
## Defines a shop's inventory, pricing, and behavior.

@export var shop_name: String = "Shop"
@export var shopkeeper_name: String = "Shopkeeper"
@export var greeting_text: String = "Welcome! What would you like?"
@export_multiline var farewell_text: String = "Come back soon!"

## Items the shop sells (always available, restocks daily)
@export var stock_items: Array[Dictionary] = []  ## [{unique_id: "health_potion", price_override: -1}]

## Max number of stock slots
@export var max_stock_slots: int = 12

## Gold the shop has for buying player items
@export var shop_gold: int = 500

## Buy price multiplier (1.0 = pay full value, 0.5 = half price from player)
@export var sell_multiplier: float = 1.0

## Sell price multiplier (1.0 = player gets full value, 0.5 = half value to player)
@export var buy_multiplier: float = 0.5

## Opening hour (0-24, -1 = always open)
@export var open_hour: int = 6

## Closing hour
@export var close_hour: int = 22


func get_item_price(item: ItemData, is_buying: bool) -> int:
	"""Calculate the actual price for buying/selling this item."""
	if is_buying:
		# Player is buying from shop → use stock price or value * sell_multiplier
		for stock_entry: Dictionary in stock_items:
			if stock_entry.get("unique_id", "") == item.unique_id:
				var override: int = stock_entry.get("price_override", -1)
				if override >= 0:
					return override
				break
		return max(1, int(item.value * sell_multiplier))
	else:
		# Shop is buying from player → value * buy_multiplier
		return max(1, int(item.value * buy_multiplier))


func is_open(current_hour: float) -> bool:
	if open_hour < 0 or close_hour < 0:
		return true
	return current_hour >= open_hour and current_hour < close_hour
