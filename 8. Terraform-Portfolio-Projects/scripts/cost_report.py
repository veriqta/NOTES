"""Compare like-for-like monthly cost exports; rates and currency are supplied, never assumed."""
import argparse
import csv
from decimal import Decimal
from pathlib import Path

def totals(path):
    result = {}
    with open(path, newline='') as f:
        for row in csv.DictReader(f):
            key = row['service'], row['currency'], row['period_days']
            result[key] = result.get(key, Decimal('0')) + Decimal(row['cost'])
    return result

def validate_windows(before, after):
    a={(k[1],k[2]) for k in before}
    b={(k[1],k[2]) for k in after}
    if a != b or len(a) != 1:
        raise ValueError('Use one matching currency and period length per comparison; normalize the exports first.')

def compare(before, after):
    result=[]
    for key in sorted(before.keys() | after.keys()):
        a,b = before.get(key,Decimal('0')),after.get(key,Decimal('0'))
        result.append((key,a,b,b-a,None if a==0 else (b-a)/a*100))
    return result

if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('before',type=Path);p.add_argument('after',type=Path)
    a=p.parse_args()
    before,after=totals(a.before),totals(a.after)
    try:
        validate_windows(before,after)
    except ValueError as error:
        raise SystemExit(str(error))
    for key,old,new,delta,percent in compare(before,after):
        print(f'{key[0]}: {old} -> {new} {key[1]}; delta={delta}; percent={"new spend" if percent is None else round(percent,2)}')
    print('TOTAL',sum(before.values()),'->',sum(after.values()))
