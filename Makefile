.PHONY: all

deploy:
	git push heroku master

console:
	heroku run rails console
