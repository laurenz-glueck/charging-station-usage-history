import pygit2
import json
import datetime
import matplotlib.pyplot as plt

repo_path = '.'
config = [
    {"name": "bahnhofsplatz", "displayName": "Bahnhofsplatz", "filePath": "history-data/history--bahnhofsplatz.json"},
    {"name": "hausen-1", "displayName": "Hausen 1", "filePath": "history-data/history--hausen-1.json"},
    {"name": "hausen-2", "displayName": "Hausen 2", "filePath": "history-data/history--hausen-1.json"}
]

repo = pygit2.Repository(repo_path)

now = datetime.datetime.now()
yesterday = now - datetime.timedelta(days=1)
yesterday_start = datetime.datetime.combine(yesterday, datetime.time.min)
yesterday_end = datetime.datetime.combine(yesterday, datetime.time.max) - datetime.timedelta(microseconds=1)

dateString = yesterday.strftime("%Y-%m-%d")

for cfg in config:
    name = cfg["name"]
    displayName = cfg["displayName"]
    file_path = cfg["filePath"]

    data = {}

    for commit in repo.walk(repo.head.target, pygit2.GIT_SORT_TIME):
        if commit.commit_time < yesterday_start.timestamp():
            break
        if (yesterday_start.timestamp() <= commit.commit_time <= yesterday_end.timestamp()) and file_path in commit.tree:
            blob = repo[commit.tree[file_path].id]
            content = blob.data.decode('utf-8')
            values = json.loads(content)
            for key, value in values.items():
                if key not in data:
                    data[key] = {}
                timestamp = datetime.datetime.fromtimestamp(commit.commit_time)
                hour = timestamp.replace(minute=0, second=0, microsecond=0)
                if hour not in data[key]:
                    data[key][hour] = []
                data[key][hour].append(value)

    x = []
    y = []

    for hour in sorted(data['availableChargePoints']):
        values = data['availableChargePoints'][hour]
        if values:
            average = int(round(sum(values) / len(values)))
        else:
            average = 0
        x.append(hour.strftime("%H:%M"))
        y.append(average)

    plt.bar(x, y, align='center')
    plt.xlabel('Hour')
    plt.ylabel('Available Charge Points')
    plt.title('Charge Point Availability "' + displayName + '" on ' + dateString)

    for i, v in enumerate(y):
        plt.text(i, v+0.02, str(v), color='black', ha='center')

    plt.yticks(range(3))
    plt.xticks(rotation=90)
    plt.savefig('history-charts/' + name + '/' + dateString + '.png')
    plt.clf()
