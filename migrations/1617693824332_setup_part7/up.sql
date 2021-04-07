CREATE FUNCTION "order"."addOnTotal"(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   total numeric := 0;
   product "order"."cartItem";
BEGIN
    IF cart."source" = 'a-la-carte' THEN
        RETURN 0;
    ELSE
        FOR product IN SELECT * FROM "order"."cartItem" WHERE "cartId" = cart.id LOOP
            total := total + COALESCE(product."addOnPrice", 0);
            IF product."isAddOn" = true THEN
                total := total + product."unitPrice";
            END IF;
        END LOOP;
        RETURN total;
    END IF;
END
$$;


CREATE FUNCTION "order"."cartBillingDetails"(cart "order".cart) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    item jsonb := '{}';
    itemTotal numeric;
    addOnTotal numeric;
    deliveryPrice numeric;
    subTotal numeric;
    tax numeric;
    taxPercent numeric;
    isTaxIncluded boolean;
    discount numeric;
    totalPrice numeric;
BEGIN
    SELECT "order"."isTaxIncluded"(cart.*) INTO isTaxIncluded;
    SELECT "order"."itemTotal"(cart.*) INTO itemTotal;
    SELECT "order"."addOnTotal"(cart.*) INTO addOnTotal;
    SELECT "order"."deliveryPrice"(cart.*) INTO deliveryPrice; 
    SELECT "order"."discount"(cart.*) INTO discount; 
    SELECT "order"."subTotal"(cart.*) INTO subTotal;
    SELECT "order".tax(cart.*) INTO tax;
    SELECT "order"."taxPercent"(cart.*) INTO taxPercent;
    SELECT "order"."totalPrice"(cart.*) INTO totalPrice;
    item:=item || jsonb_build_object('isTaxIncluded', isTaxIncluded);
    item:=item || jsonb_build_object('discount', jsonb_build_object('value', discount, 'label', 'Discount'));
    item:=item || jsonb_build_object('loyaltyPointsUsed', jsonb_build_object('value', cart."loyaltyPointsUsed", 'label', 'Loyalty Points'));
    item:=item || jsonb_build_object('walletAmountUsed', jsonb_build_object('value', cart."walletAmountUsed", 'label', 'Wallet Amount'));
    item:=item || jsonb_build_object('itemTotal', jsonb_build_object('value', itemTotal, 'description', 'Includes your base price and add on price.', 'label','Item Total', 'comment', CONCAT('Includes add on total of ', '{{',COALESCE(addOnTotal,0),'}}')));
    item:=item || jsonb_build_object('deliveryPrice', jsonb_build_object('value', deliveryPrice, 'description', '', 'label','Delivery Fee', 'comment', ''));
    IF isTaxIncluded = false THEN
        item:=item || jsonb_build_object('subTotal', jsonb_build_object('value', subTotal, 'description', '', 'label','Sub Total', 'comment', ''));
        item:=item || jsonb_build_object('tax', jsonb_build_object('value', tax, 'description', '', 'label','Tax', 'comment', CONCAT('Your tax is calculated at ', taxPercent,'%')));
        item:=item || jsonb_build_object('totalPrice', jsonb_build_object('value', totalPrice, 'description', '', 'label','Total Price', 'comment', ''));
    ELSE
        item:=item || jsonb_build_object('totalPrice', jsonb_build_object('value', totalPrice, 'description', '', 'label','Total Price', 'comment', CONCAT('Tax inclusive of ', '{{',tax,'}}', ' at ', taxPercent, '%')));
    END IF;
    RETURN item;
END
$$;
CREATE FUNCTION "order"."clearFulfillmentInfo"(cartid integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "order"."cart"
    SET "fulfillmentInfo" = NULL
    WHERE id = cartId;
END
$$;
