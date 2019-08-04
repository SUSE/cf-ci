from locust import HttpLocust, TaskSet, task
import string
import random

def str_generator(size=6, chars=string.ascii_uppercase + string.digits):
    return ''.join(random.SystemRandom().choice(chars) for _ in range(size))

class UserBehavior(TaskSet):

    def on_start(self):
        print('starting...')
        self.client.verify = False
    
    def on_stop(self):
        print('stopping...')
        return
    
    # 50% will be browsing...
    @task(5)
    def browse(self):
        print('browsing...')
        self.client.get("/albums")     
    
        
    # 30% will be adding...
    @task(3)
    def add(self):
        """ Add albums with random content"""
        print('adding...')
        self.client.post("/albums", json={"title": str_generator(10), "artist": str_generator(8),
                                      "releaseYear": random.SystemRandom().randint(1950, 2019),
                                     "genre": random.SystemRandom().choice(['RocknRoll', 'R&B', 'Pop', 'Fusion'])})
   
    # 10% will be updating...
    @task(1)
    def update(self):
       """ Update a random album from the list retrieved from a browse""" 
       json = self.client.get("/albums").json()
       ids = [ j['id'] for j in json ]
       if ids:
        print('updating...')
        self.client.post("/albums", json={"id": random.SystemRandom().choice(ids), 
            "title": str_generator(10), "artist":str_generator(8),
            "releaseYear":random.SystemRandom().randint(1950, 2019),
            "genre": random.SystemRandom().choice(['RocknRoll', 'R&B', 'Pop', 'Fusion'])})
    
    # and 10% will be deleting.    
    @task(1)
    def delete(self):
        "Delete a random album from the list retrieved from a browse"
        json = self.client.get("/albums").json()
        ids = [ j['id'] for j in json ]
        if ids:
            print('deleting...')
            response = self.client.delete("/albums"f'/{random.SystemRandom().choice(ids)}')
            print(response.status_code)


class WebsiteUser(HttpLocust):
    task_set = UserBehavior
    min_wait = 5000
    max_wait = 9000

