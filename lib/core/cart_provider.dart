import 'package:flutter/material.dart';
import '../models.dart';
class CartProvider with ChangeNotifier {
  List<CartItem> _items = [];
  double _discountValue = 0.0;
  bool _isDiscountPercentage = false;
  String? orderIdentifier;
  OrderType _orderType = OrderType.onSite;
  String _originalSource = 'caisse';
  List<CartItem> get items => [..._items];
  double get discountValue => _discountValue;
  bool get isDiscountPercentage => _isDiscountPercentage;
  OrderType get orderType => _orderType;
  String get originalSource => _originalSource;
  bool get hasUnsentItems => _items.any((item) => !item.isSentToKitchen);
  int get subTotalCents {
    return _items.fold(0, (sum, item) => sum + item.totalCents);
  }
  int get discountAmountCents {
    if (_discountValue <= 0) return 0;
    if (_isDiscountPercentage) {
      return (subTotalCents * (_discountValue / 100)).round();
    } else {
      return (_discountValue * 100).round();
    }
  }
  int get totalCents {
    final result = subTotalCents - discountAmountCents;
    return result < 0 ? 0 : result;
  }
  double get subTotal => subTotalCents / 100.0;
  double get discountAmount => discountAmountCents / 100.0;
  double get total => totalCents / 100.0;
  double get totalVat {
    double totalVatCents = 0;
    for (var item in _items) {
      final itemTotalCents = item.totalCents;
      final vatMultiplier = item.vatRate / 100;
      final itemVatCents =
          itemTotalCents - (itemTotalCents / (1 + vatMultiplier));
      totalVatCents += itemVatCents;
    }
    if (discountAmountCents > 0 && subTotalCents > 0) {
      final discountRatio =
          (subTotalCents - discountAmountCents) / subTotalCents;
      return (totalVatCents * discountRatio) / 100.0;
    }
    return totalVatCents / 100.0;
  }
  void setOrderType(OrderType type) {
    _orderType = type;
    notifyListeners();
  }
  void addItem(CartItem item) {
    _items.add(item);
    notifyListeners();
  }
  void removeItem(CartItem item) {
    _items.removeWhere((cartItem) => cartItem.id == item.id);
    notifyListeners();
  }
  void replaceItem(CartItem oldItem, CartItem newItem) {
    final index = _items.indexWhere((item) => item.id == oldItem.id);
    if (index != -1) {
      _items[index] = newItem;
      notifyListeners();
    }
  }
  void incrementItemQuantity(CartItem item) {
    final index = _items.indexWhere((cartItem) => cartItem.id == item.id);
    if (index != -1) {
      _items[index].quantity++;
      notifyListeners();
    }
  }
  void decrementItemQuantity(CartItem item) {
    final index = _items.indexWhere((cartItem) => cartItem.id == item.id);
    if (index != -1) {
      if (_items[index].quantity > 1) {
        _items[index].quantity--;
      } else {
        removeItem(_items[index]);
      }
      notifyListeners();
    }
  }
  void setOrderIdentifier(String? identifier) {
    orderIdentifier = identifier;
    notifyListeners();
  }
  void markUnsentItemsAsSent() {
    for (var item in _items) {
      if (!item.isSentToKitchen) {
        item.isSentToKitchen = true;
      }
    }
    notifyListeners();
  }
  void applyDiscount({required double value, required bool isPercentage}) {
    _discountValue = value;
    _isDiscountPercentage = isPercentage;
    notifyListeners();
  }
  void removeDiscount() {
    _discountValue = 0.0;
    _isDiscountPercentage = false;
    notifyListeners();
  }
  void clearCart() {
    _items = [];
    orderIdentifier = null;
    _orderType = OrderType.onSite;
    _originalSource = 'caisse';
    removeDiscount();
    notifyListeners();
  }
  void loadCart(List<CartItem> newItems, String identifier,
      {OrderType type = OrderType.onSite, String source = 'caisse'}) {
    _items = newItems;
    orderIdentifier = identifier;
    _orderType = type;
    _originalSource = source;
    removeDiscount();
    notifyListeners();
  }
  void updateVatRates(
      {required OrderType orderType,
      required Map<String, FranchiseeMenuItem> settings}) {
    for (var item in _items) {
      final productSettings = settings[item.product.productId];
      if (productSettings != null) {
        if (productSettings.vatRate == 20.0) {
          item.vatRate = 20.0;
        } else {
          item.vatRate = (orderType == OrderType.takeaway)
              ? productSettings.takeawayVatRate
              : productSettings.vatRate;
        }
      }
    }
    notifyListeners();
  }
}
