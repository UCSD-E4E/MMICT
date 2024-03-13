# MMICT

To clone:
```git clone --recurse-submodules git@github.com:UCSD-E4E/MMICT.git```

## Building and Running the Mangrove Monitoring application using Docker!

There are two Docker compose files to build the containers needed to run the Mangrove Monitoring application, a dev and production one.

- The dev compose file, ```docker-compose.dev.yml``` is used to build all containers in our app for development purposes. This compose file is suited for one Docker host, meaning one Docker engine instance (For example running it locally on the computer you are doing development on).

- The production compose file, ```docker-compose.yml``` is used to build all containers and run them on a Docker swarm. We need this to ultilize overlay networks in our app and segemnt different services in of our application for security purposes. For now its configured to also run locally, but future plans include migrating it from Docker Sawrm to AWS ECS with images of our services potentially being stored in AWS as well. This is still a WIP.

To build and run the development version of the Mangrove Monitoring application:
- Make sure you have Docker installed. It is also useful to get familiar with the GUI for the DOcker enginer.
- In the directory where the ```docker-compose.dev.yml``` is located, run:
```docker compose -f docker-compose.dev.yml build && docker compose -f docker-compose.dev.yml up```


