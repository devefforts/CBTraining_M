"""Order is a class: it holds data and knows how to add an item and total itself."""


class Order:
    def __init__(self, order_id, customer):
        self.order_id = order_id
        self.customer = customer
        self.items = []

    def add_item(self, name, price):
        self.items.append((name, price))

    def total(self):
        return sum(price for _name, price in self.items)
