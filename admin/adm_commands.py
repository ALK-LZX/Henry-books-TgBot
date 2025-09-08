from aiogram import types
from aiogram.filters import Command
import asyncio
import os
from dotenv import load_dotenv
from aiogram.fsm.context import FSMContext
from aiogram import F
from aiogram.fsm.state import State, StatesGroup
from kbs.kbs_user import *
from kbs.kbs_adm import *
import json

class AdmStates(StatesGroup):
    waiting_json = State()

load_dotenv()
ADMIN_ID = int(os.getenv('ADMIN_ID'))

async def addbooksadm(message: types.Message, state: FSMContext):
    if message.from_user.id == ADMIN_ID:
        await state.set_state(AdmStates.waiting_json)
        bot_message = await message.answer(text = 'С возвращением, мисс.')
        await asyncio.sleep(3)
        await bot_message.delete()
        await message.answer(text = 'Что добавляем?', reply_markup=kb_adm_cancel)
    else:
        pass


async def adm_json(message: types.Message, state: FSMContext, bot):
    if not message.document.file_name.endswith('.json'):
        await message.answer('Не json.')
        return

    try:
        file_info = await bot.get_file(message.document.file_id)
        file_content = await bot.download_file(file_info.file_path)

        new_books = json.loads(file_content.read().decode('utf-8'))

        with open('db/all_books.json', 'r', encoding='utf-8') as oldf:
            current_books = json.load(oldf)

        for category, books in new_books.items():
            if category in current_books:
                current_books[category].extend(books)
            else:
                current_books[category] = books

        with open('db/all_books.json', 'w', encoding='utf-8') as file:
            json.dump(current_books, file, ensure_ascii=False, indent=2)

        await message.answer('Я записал книги.')
        await state.clear()
    except Exception as e:
        await message.answer(f'Ошибка: {e}')
        await state.clear()
       

async def adm_cancel(callback: types.CallbackQuery, state: FSMContext):
    await state.clear()
    await callback.message.edit_text('Буду ждать в другой раз.', reply_markup=None)
    await callback.answer()

def register_admin_handlers(dp, bot):  
    dp.message(Command('admin'))(addbooksadm)

    async def handle_admin_document(message: types.Message, state: FSMContext):
        if message.from_user.id == ADMIN_ID:
            await adm_json(message, state, bot)
    
    dp.message(AdmStates.waiting_json, F.document)(handle_admin_document)

    dp.callback_query(F.data == 'adm_cancel')(adm_cancel)