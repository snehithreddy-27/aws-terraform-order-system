import json
import boto3
from boto3.dynamodb.conditions import Key
from decimal import Decimal

dynamodb = boto3.resource('dynamodb', region_name='us-east-2')
table = dynamodb.Table('ordersTable-tf')

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)

def lambda_handler(event, context):
    try:
        user_id = event.get('pathParameters', {}).get('userId')

        if not user_id:
            return resp(400, {'error': 'userId is required'})

        result = table.query(
            KeyConditionExpression=Key('UserId').eq(user_id)
        )

        items = result.get('Items', [])

        return resp(200, {
            'userId': user_id,
            'totalOrders': len(items),
            'orders': items
        })

    except Exception as e:
        return resp(500, {'error': str(e)})

def resp(code, body):
    return {
        'statusCode': code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'GET,OPTIONS'
        },
        'body': json.dumps(body, cls=DecimalEncoder)
    }