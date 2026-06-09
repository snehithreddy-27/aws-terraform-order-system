import json
import boto3
import uuid
from datetime import datetime, timezone
from decimal import Decimal

dynamodb = boto3.resource('dynamodb', region_name='us-east-2')
table = dynamodb.Table('ordersTable-tf')

ses = boto3.client('ses', region_name='us-east-2')
SENDER_EMAIL = 'snehithreddy27.ss@gmail.com'

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        user_id  = body.get('UserId')
        name     = body.get('name')
        quantity = body.get('quantity')
        price    = body.get('price')
        email    = body.get('email')

        if not all([user_id, name, quantity, price, email]):
            return resp(400, {'error': 'All fields required'})

        order_id = str(uuid.uuid4())
        item = {
            'UserId':    user_id,
            'name':      name,
            'quantity':  int(quantity),
            'price':     str(price),
            'orderId':   order_id,
            'email':     email,
            'createdAt': datetime.now(timezone.utc).isoformat()
        }
        table.put_item(Item=item)

        ses.send_email(
            Source=SENDER_EMAIL,
            Destination={'ToAddresses': [email]},
            Message={
                'Subject': {'Data': 'Order Confirmed!'},
                'Body': {
                    'Text': {
                        'Data': f"""Hello!

Your order has been confirmed.

Order ID:  {order_id}
Item:      {name}
Quantity:  {quantity}
Price:     ${price}

Thank you for your order!"""
                    }
                }
            }
        )

        return resp(201, {'message': 'Order placed!', 'orderId': order_id})
    except Exception as e:
        return resp(500, {'error': str(e)})

def resp(code, body):
    return {
        'statusCode': code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'POST,OPTIONS'
        },
        'body': json.dumps(body)
    }