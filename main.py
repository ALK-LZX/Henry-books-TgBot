from aiogram import Bot, Dispatcher, types
from aiogram.filters import Command
import asyncio
import os
from dotenv import load_dotenv
from kbs.kbs_user import *
from users.us_commands import register_user_handlers
from admin.adm_commands import register_admin_handlers
import logging
logging.basicConfig(level=logging.INFO)

load_dotenv()
from db.database import init_db, set_first_interaction_date
init_db()

ADMIN_ID = int(os.getenv('ADMIN_ID'))
dp = Dispatcher()
bot=Bot(token=os.getenv('BOT_TOKEN'))

register_user_handlers(dp)
register_admin_handlers(dp, bot)

@dp.message(Command('start'))
async def start_handler(message: types.Message):
    user_id = message.from_user.id
    print(f"User ID: {user_id}") 
    
    set_first_interaction_date(user_id)
    
    await message.delete() 
    await message.answer(text = 'Я ждал Вас, человек. Чего же ждете Вы?', reply_markup = kb_start)

async def main():
    print('работает')
    await dp.start_polling(bot, drop_pending_updates=True)
    

if __name__ == '__main__':
    asyncio.run(main())